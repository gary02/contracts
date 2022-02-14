//SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {DSTest} from "ds-test/test.sol";
import {console} from "./utils/Console.sol";
import {Hevm} from "./utils/Hevm.sol";
import {Logbook} from "../Logbook/Logbook.sol";

contract LogbookTest is DSTest {
    Logbook private logbook;

    Hevm constant vm = Hevm(HEVM_ADDRESS);

    address constant DEPLOYER = address(176);
    address constant TRAVELOGGERS_OWNER = address(177);
    address constant PUBLIC_SALE_MINTER = address(178);
    address constant ATTACKER = address(179);
    address constant APPROVED = address(180);

    uint256 constant _PUBLIC_SALE_ON = 1;
    uint256 constant _PUBLIC_SALE_OFF = 2;

    uint256 constant CLAIM_TOKEN_START_ID = 1;
    uint256 constant CLAIM_TOKEN_END_ID = 1500;

    event SetTitle(uint256 indexed tokenId, string title);

    event SetDescription(uint256 indexed tokenId, string description);

    event SetForkPrice(uint256 indexed tokenId, uint256 amount);

    event Publish(uint256 indexed tokenId, address indexed author, bytes32 indexed contentHash, string content);

    event Fork(
        uint256 indexed tokenId,
        uint256 indexed newTokenId,
        address indexed owner,
        bytes32 contentHash,
        uint256 amount
    );

    event Donate(uint256 indexed tokenId, address indexed donor, uint256 amount);

    function setUp() public {
        vm.prank(DEPLOYER);
        logbook = new Logbook("Logbook", "LBK");
    }

    /**
     * Claim
     */
    function _claimToTraveloggersOwner() private {
        vm.prank(DEPLOYER);
        logbook.claim(TRAVELOGGERS_OWNER, CLAIM_TOKEN_START_ID);
        assertEq(logbook.ownerOf(CLAIM_TOKEN_START_ID), TRAVELOGGERS_OWNER);
        assertEq(logbook.balanceOf(TRAVELOGGERS_OWNER), 1);
    }

    function testClaim() public {
        // only owner
        vm.prank(PUBLIC_SALE_MINTER);
        vm.expectRevert("Ownable: caller is not the owner");
        logbook.claim(TRAVELOGGERS_OWNER, CLAIM_TOKEN_END_ID);

        // token has not been claimed yet
        vm.expectRevert("ERC721: owner query for nonexistent token");
        logbook.ownerOf(CLAIM_TOKEN_START_ID);

        assertEq(logbook.balanceOf(TRAVELOGGERS_OWNER), 0);

        // claim
        _claimToTraveloggersOwner();

        // token can't be claimed again
        vm.prank(DEPLOYER);
        vm.expectRevert("ERC721: token already minted");
        logbook.claim(TRAVELOGGERS_OWNER, CLAIM_TOKEN_START_ID);

        // invalid token id
        vm.prank(DEPLOYER);
        vm.expectRevert("invalid logrs id");
        logbook.claim(TRAVELOGGERS_OWNER, CLAIM_TOKEN_START_ID - 1);

        vm.prank(DEPLOYER);
        vm.expectRevert("invalid logrs id");
        logbook.claim(TRAVELOGGERS_OWNER, CLAIM_TOKEN_END_ID + 1);
    }

    /**
     * Public Sale
     */
    function testPublicSale() public {
        // not started
        vm.expectRevert("public sale is not started");
        logbook.publicSaleMint();

        // turn on: set state (1/2)
        vm.prank(DEPLOYER);
        logbook.togglePublicSale();
        vm.prank(PUBLIC_SALE_MINTER);
        vm.expectRevert("public sale is not started");
        logbook.publicSaleMint();

        // turn on: set price (2/2)
        vm.prank(DEPLOYER);
        uint256 price = 0.03 ether;
        logbook.setPublicSalePrice(price);
        assertEq(logbook.publicSalePrice(), price);

        // mint
        uint256 deployerBalanceBefore = DEPLOYER.balance;
        vm.deal(PUBLIC_SALE_MINTER, 1 ether);
        vm.prank(PUBLIC_SALE_MINTER);
        uint256 tokenId = logbook.publicSaleMint{value: price}();
        assertEq(tokenId, CLAIM_TOKEN_END_ID + 1);
        assertEq(logbook.ownerOf(tokenId), PUBLIC_SALE_MINTER);

        // deployer receives ether
        assertEq(DEPLOYER.balance, deployerBalanceBefore + price);

        // not engough ether to mint
        vm.expectRevert("value too small");
        vm.prank(PUBLIC_SALE_MINTER);
        logbook.publicSaleMint{value: price - 0.01 ether}();
    }

    /**
     * Title, Description, Fork Price, Publish...
     */
    function testSetTitle() public {
        _claimToTraveloggersOwner();
        string memory title = "Sit deserunt nulla aliqua ex nisi";

        // set title
        vm.prank(TRAVELOGGERS_OWNER);
        vm.expectEmit(true, true, false, false);
        emit SetTitle(CLAIM_TOKEN_START_ID, title);
        logbook.setTitle(CLAIM_TOKEN_START_ID, title);

        // only logbook owner
        vm.prank(ATTACKER);
        vm.expectRevert("caller is not owner nor approved");
        logbook.setTitle(CLAIM_TOKEN_START_ID, title);

        // approve other address
        vm.startPrank(TRAVELOGGERS_OWNER);
        logbook.approve(APPROVED, CLAIM_TOKEN_START_ID);
        logbook.getApproved(CLAIM_TOKEN_START_ID);
        vm.stopPrank();

        vm.prank(APPROVED);
        logbook.setTitle(CLAIM_TOKEN_START_ID, title);
    }

    // Publish: gas?
    // Donate: gas? (long list)
    // Fork: gas? (long list)
    // Withdraw
    // BPS
}
