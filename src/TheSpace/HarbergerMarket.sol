//SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

import "./AccessRoles.sol";

/**
 * @dev Market place with Harberger tax. Market attaches one ERC20 contract as currency.
 */
contract HarbergerMarket is ERC721Enumerable, Multicall, AccessRoles {
    /**
     * Override interface
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * Error types
     */
    error PriceTooLow();
    error Unauthorized();
    error TokenNotExists();
    error InvalidTokenId(uint256 min, uint256 max);

    /**
     * Event types
     */

    /**
     * @dev Emitted when a token changes price.
     */
    event Price(uint256 indexed tokenId, uint256 price, address indexed owner);

    /**
     * @dev Emitted when tax configuration updates.
     */
    event Config(ConfigOptions indexed option, uint256 value);

    /**
     * @dev Emitted when tax is collected.
     */
    event Tax(uint256 indexed tokenId, uint256 amount);

    /**
     * @dev Emitted when UBI is distributed.
     */
    event UBI(uint256 indexed tokenId, uint256 amount);

    /**
     * Global setup total supply and currency address
     */

    /**
     * @dev Total possible NFTs
     */
    uint256 public _totalSupply = 1000000;

    /**
     * @dev ERC20 token used as currency
     */
    ERC20 public currency;

    /**
     * State variables for each token
     */

    /**
     * @dev Record of token. Use block number to record tax collection time.
     *
     * TODO: more efficient storage scheme, see: https://medium.com/@novablitz/storing-structs-is-costing-you-gas-774da988895e
     */
    struct TokenRecord {
        uint256 price;
        uint256 lastTaxCollection;
        uint256 ubiWithdrawn;
    }

    /**
     * @dev Record of each token.
     */
    mapping(uint256 => TokenRecord) public tokenRecord;

    /**
     * Tax related global states.
     */

    /**
     * @dev Record of treasury state.
     * TODO: more efficient storage scheme
     */
    struct TreasuryRecord {
        uint256 accumulatedUBI;
        uint256 accumulatedTreasury;
        uint256 treasuryWithdrawn;
    }

    TreasuryRecord public treasuryRecord;

    /**
     * @dev Tax configuration of market.
     * - taxRate: Tax rate in bps every 1000 blocks
     * - treasuryShare: Share to treasury in bps.
     */
    enum ConfigOptions {
        taxRate,
        treasuryShare
    }

    struct TaxConfig {
        uint256 taxRate;
        uint256 treasuryShare;
    }

    // Setting for tax config
    mapping(ConfigOptions => uint256) public taxConfig;

    /**
     * @dev Create Property contract, setup attached currency contract, setup tax rate
     */
    constructor(
        string memory propertyName_,
        string memory propertySymbol_,
        address currencyAddress_,
        address admin_,
        address treasury_
    ) ERC721(propertyName_, propertySymbol_) AccessRoles(admin_, treasury_) {
        // initialize currency contract
        currency = ERC20(currencyAddress_);

        // default config
        taxConfig[ConfigOptions.taxRate] = 10;
        taxConfig[ConfigOptions.treasuryShare] = 500;
    }

    /**
     * @dev See {IERC20-totalSupply}. Always return total possible amount of supply, instead of current token in circulation.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * Admin only
     */

    /**
     * @dev Set the tax config for current contract. ADMIN_ROLE only.
     */
    function setTaxConfig(ConfigOptions option, uint256 value) external onlyRole(ADMIN_ROLE) {
        taxConfig[option] = value;

        emit Config(option, value);
    }

    /**
     * @dev Withdraw available treasury. TREASURY_ROLE only.
     */
    function withdrawTreasury() external onlyRole(TREASURY_ROLE) {
        uint256 amount = treasuryRecord.accumulatedTreasury - treasuryRecord.treasuryWithdrawn;

        currency.transfer(msg.sender, amount);
    }

    /**
     * Read and write of token state
     */

    /**
     * @dev Returns the current price of an Harberger property with token id.
     */
    function getPrice(uint256 tokenId) public view returns (uint256 price) {
        return tokenRecord[tokenId].price;
    }

    /**
     * @dev Set the current price of an Harberger property with token id.
     *
     * Emits a {Price} event.
     */
    function setPrice(uint256 tokenId, uint256 price) external {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert Unauthorized();
        if (price == getPrice(tokenId)) return;

        bool success = collectTax(tokenId);
        if (success) _setPrice(tokenId, price);
    }

    /**
     * @dev Returns the current owner of an Harberger property with token id. If token does not exisit, return address(0)
     */
    function getOwner(uint256 tokenId) external view returns (address owner) {
        return _exists(tokenId) ? ownerOf(tokenId) : address(0);
    }

    /**
     * @dev Purchase property with bid higher than current price. Clear tax for owner before transfer.
     * TODO: check security implications
     */
    function bid(uint256 tokenId, uint256 price) external {
        if (_exists(tokenId)) {
            // skip if already own
            address owner = ownerOf(tokenId);
            if (owner == msg.sender) return;

            uint256 askPrice = getPrice(tokenId);
            if (price < askPrice) revert PriceTooLow();

            // clear tax
            bool success = collectTax(tokenId);

            if (success) {
                // successfully clear tax
                currency.transferFrom(msg.sender, owner, askPrice);
                _safeTransfer(owner, msg.sender, tokenId, "");

                return;
            }
        }

        // if token does not exists yet, or token is defaulted
        // mint token to current sender for free
        if (tokenId > _totalSupply || tokenId < 1) revert InvalidTokenId(1, _totalSupply);
        _safeMint(msg.sender, tokenId);
        // update tax record
        tokenRecord[tokenId].lastTaxCollection = block.number;
    }

    /**
     * Tax & UBI
     */

    /**
     * @dev calculate tax for a token
     */
    function getTax(uint256 tokenId) public view returns (uint256) {
        // calculate tax
        // `1000` for every `1000` blocks, `10000` for conversion from bps
        return
            (getPrice(tokenId) *
                taxConfig[ConfigOptions.taxRate] *
                (block.number - tokenRecord[tokenId].lastTaxCollection)) / (1000 * 10000);
    }

    /**
     * @dev Collect outstanding property tax for a given token, put token on tax sale if obligation not met.
     *
     * Emits a {Tax} event and a {Price} event (when properties are put on tax sale).
     */
    function collectTax(uint256 tokenId) public returns (bool) {
        if (!_exists(tokenId)) revert TokenNotExists();

        uint256 tax = getTax(tokenId);
        if (tax > 0) {
            // calculate collectable amount
            address taxpayer = ownerOf(tokenId);
            uint256 allowance = currency.allowance(taxpayer, address(this));
            uint256 balance = currency.balanceOf(taxpayer);
            uint256 collectable = _min(allowance, balance);

            // calculate amount to be collected, the smaller one of tax and collectable
            // then update accumulatedUBI
            uint256 collecting = _min(collectable, tax);

            if (collecting > 0) {
                currency.transferFrom(taxpayer, address(this), collecting);
                emit Tax(tokenId, collecting);

                // update accumulated ubi
                treasuryRecord.accumulatedUBI +=
                    (collecting * (10000 - taxConfig[ConfigOptions.treasuryShare])) /
                    10000;

                // update accumulated treasury
                treasuryRecord.accumulatedTreasury += (collecting * taxConfig[ConfigOptions.treasuryShare]) / 10000;
            }

            // default if tax is not fully collected
            if (tax > collectable) {
                // default
                _default(tokenId);
                return false;
            } else {
                // collect tax
                tokenRecord[tokenId].lastTaxCollection = block.number;
                return true;
            }
        } else {
            // no tax for price 0
            tokenRecord[tokenId].lastTaxCollection = block.number;
            return true;
        }
    }

    /**
     * @dev UBI available for withdraw on given token.
     */
    function ubiAvailable(uint256 tokenId) public view returns (uint256) {
        return treasuryRecord.accumulatedUBI / _totalSupply - tokenRecord[tokenId].ubiWithdrawn;
    }

    /**
     * @dev Withdraw UBI on given token.
     */
    function withdrawUbi(uint256 tokenId) external {
        uint256 ubi = ubiAvailable(tokenId);

        if (ubi > 0) {
            tokenRecord[tokenId].ubiWithdrawn += ubi;
            currency.transfer(ownerOf(tokenId), ubi);

            emit UBI(tokenId, ubi);
        }
    }

    function _default(uint256 tokenId) internal {
        _burn(tokenId);
        _setPrice(tokenId, 0);
    }

    function _setPrice(uint256 tokenId, uint256 price) internal {
        // update price in tax record
        tokenRecord[tokenId].price = price;

        address owner = _exists(tokenId) ? ownerOf(tokenId) : address(0);

        // emit events
        emit Price(tokenId, price, owner);
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
