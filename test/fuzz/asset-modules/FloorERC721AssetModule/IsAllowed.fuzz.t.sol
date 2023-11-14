/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

import { FloorERC721AssetModule_Fuzz_Test } from "./_FloorERC721AssetModule.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "isAllowed" of contract "FloorERC721AssetModule".
 */
contract IsAllowed_FloorERC721AssetModule_Fuzz_Test is FloorERC721AssetModule_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        FloorERC721AssetModule_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_isAllowed_Positive(uint256 start, uint256 end, uint256 id) public {
        start = bound(start, 0, type(uint256).max - 1);
        end = bound(end, start + 1, type(uint256).max);
        id = bound(id, start, end);

        vm.prank(users.creatorAddress);
        floorERC721AssetModule.addAsset(address(mockERC721.nft2), start, end, oraclesNft2ToUsd);

        assertTrue(floorERC721AssetModule.isAllowed(address(mockERC721.nft2), id));
    }

    function testFuzz_Success_isAllowed_Negative_WrongAddress(address randomAsset) public {
        assertFalse(floorERC721AssetModule.isAllowed(randomAsset, 0));
    }

    function testFuzz_Success_isAllowed_Negative_IdBelowRange(uint256 start, uint256 end, uint256 id) public {
        start = bound(start, 1, type(uint256).max - 1);
        end = bound(end, start + 1, type(uint256).max);
        id = bound(id, 0, start - 1);

        vm.prank(users.creatorAddress);
        floorERC721AssetModule.addAsset(address(mockERC721.nft2), start, end, oraclesNft2ToUsd);

        assertFalse(floorERC721AssetModule.isAllowed(address(mockERC721.nft2), id));
    }

    function testFuzz_Success_isAllowed_Negative_IdAboveRange(uint256 start, uint256 end, uint256 id) public {
        start = bound(start, 1, type(uint256).max - 2);
        end = bound(end, start + 1, type(uint256).max - 1);
        id = bound(id, end + 1, type(uint256).max);

        vm.prank(users.creatorAddress);
        floorERC721AssetModule.addAsset(address(mockERC721.nft2), start, end, oraclesNft2ToUsd);

        assertFalse(floorERC721AssetModule.isAllowed(address(mockERC721.nft2), id));
    }
}