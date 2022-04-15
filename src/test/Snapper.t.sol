// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {DSTest} from "ds-test/test.sol";
import {Hevm} from "./utils/Hevm.sol";
import {Snapper} from "../Snapper/Snapper.sol";

contract SnapperTest is DSTest {
    Snapper private snapper;

    Hevm constant vm = Hevm(HEVM_ADDRESS);

    address constant DEPLOYER = address(176);
    string constant CID0 = "QmYCw8HExhNnoxvc4FQQwtjK5bTZ3NKU2Np6TbNBX2ypW0";
    string constant CID1 = "QmYCw8HExhNnoxvc4FQQwtjK5bTZ3NKU2Np6TbNBX2ypWJ";
    string constant CID2 = "QmSmGAGMGxvKADmvYYQYHTD4BobZBJcSvZffjM6QhUC74E";

    event Snapshot(uint256 indexed block, string cid);
    event Delta(uint256 indexed block, string cid);

    function setUp() public {
        vm.roll(2);

        // emit initial Snapshot Event when creating contracts.
        // vm.expectEmit(true, false, false, true);
        // emit Snapshot(1, CID1);

        vm.prank(DEPLOYER);
        snapper = new Snapper(1, CID0);
    }

    function testCannotTakeSnapshotByNotOwner() public {
        vm.roll(5);
        vm.expectRevert("Ownable: caller is not the owner");
        snapper.takeSnapshot(1, 2, CID1, CID2);
    }

    function testCannotTakeSnapshotWrongLastBlock() public {
        vm.roll(5);

        vm.prank(DEPLOYER);
        vm.expectRevert("`lastSnapshotBlock_` must be equal to `latestSnapshotBlock` returned by `latestSnapshotInfo`");
        snapper.takeSnapshot(0, 2, CID1, CID2);

        vm.prank(DEPLOYER);
        vm.expectRevert("`lastSnapshotBlock_` must be equal to `latestSnapshotBlock` returned by `latestSnapshotInfo`");
        snapper.takeSnapshot(3, 4, CID1, CID2);

        vm.prank(DEPLOYER);
        snapper.takeSnapshot(1, 2, CID1, CID2);
    }

    function testCannotTakeSnapshotWrongSnapshotBlock() public {
        vm.roll(5);

        vm.prank(DEPLOYER);
        vm.expectRevert("`snapshotBlock` must be greater than `latestSnapshotBlock` returned by `latestSnapshotInfo`");
        snapper.takeSnapshot(1, 1, CID1, CID2);

        vm.prank(DEPLOYER);
        vm.expectRevert("`snapshotBlock` must be greater than `latestSnapshotBlock` returned by `latestSnapshotInfo`");
        snapper.takeSnapshot(1, 0, CID1, CID2);
    }

    function testTakeSnapshot() public {
        vm.roll(5);

        uint256 snapshotBlock = 3;

        (uint256 bk1, string memory cid1) = snapper.latestSnapshotInfo();
        assertEq(bk1, 1);
        assertEq(cid1, CID0);

        // takeSnapshot will emit Snapshot and Delta events.
        vm.expectEmit(true, false, false, true);
        emit Snapshot(snapshotBlock, CID1);
        vm.expectEmit(true, false, false, true);
        emit Delta(snapshotBlock, CID2);

        vm.prank(DEPLOYER);
        snapper.takeSnapshot(1, snapshotBlock, CID1, CID2);

        // takeSnapshot will update latestSnapshotInfo
        (uint256 bk2, string memory cid2) = snapper.latestSnapshotInfo();
        assertEq(bk2, snapshotBlock);
        assertEq(cid2, CID1);
    }
}
