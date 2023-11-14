/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

import { AbstractPrimaryAssetModule_Fuzz_Test } from "./_AbstractPrimaryAssetModule.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "processIndirectWithdrawal" of contract "AbstractPrimaryAssetModule".
 */
contract ProcessIndirectWithdrawal_AbstractPrimaryAssetModule_Fuzz_Test is AbstractPrimaryAssetModule_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        AbstractPrimaryAssetModule_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_processIndirectWithdrawal_NonMainRegistry(
        PrimaryAssetModuleAssetState memory assetState,
        address unprivilegedAddress_,
        uint256 exposureUpperAssetToAsset,
        int256 deltaExposureUpperAssetToAsset
    ) public {
        // Given "caller" is not the Main Registry.
        vm.assume(unprivilegedAddress_ != address(mainRegistryExtension));

        // And: State is persisted.
        setPrimaryAssetModuleAssetState(assetState);

        // When: Asset is indirectly withdrawn.
        // Then: The transaction reverts with "AAM: ONLY_MAIN_REGISTRY".
        vm.startPrank(unprivilegedAddress_);
        vm.expectRevert("AAM: ONLY_MAIN_REGISTRY");
        assetModule.processIndirectWithdrawal(
            assetState.creditor,
            assetState.asset,
            assetState.assetId,
            exposureUpperAssetToAsset,
            deltaExposureUpperAssetToAsset
        );
        vm.stopPrank();
    }

    function testFuzz_Revert_processIndirectWithdrawal_OverExposure(
        PrimaryAssetModuleAssetState memory assetState,
        uint256 exposureUpperAssetToAsset,
        uint256 deltaExposureUpperAssetToAsset
    ) public {
        // Given: "exposureAsset" is bigger thantype(uint128).max (test-case).
        // And: "exposureAssetLast" does not overflow.
        deltaExposureUpperAssetToAsset = bound(
            deltaExposureUpperAssetToAsset, uint256(type(uint128).max) + 1 - assetState.exposureAssetLast, INT256_MAX
        );
        deltaExposureUpperAssetToAsset = bound(
            deltaExposureUpperAssetToAsset,
            uint256(type(uint128).max) + 1 - assetState.exposureAssetLast,
            type(uint256).max - assetState.exposureAssetLast
        );

        // And: State is persisted.
        setPrimaryAssetModuleAssetState(assetState);

        // When: Asset is indirectly withdrawn.
        // Then: The transaction reverts with "APAM_PIW: Overflow".
        vm.startPrank(address(mainRegistryExtension));
        vm.expectRevert("APAM_PIW: Overflow");
        assetModule.processIndirectWithdrawal(
            assetState.creditor,
            assetState.asset,
            assetState.assetId,
            exposureUpperAssetToAsset,
            int256(deltaExposureUpperAssetToAsset)
        );
        vm.stopPrank();
    }

    function testFuzz_Success_processIndirectWithdrawal_positiveDelta(
        PrimaryAssetModuleAssetState memory assetState,
        uint256 exposureUpperAssetToAsset,
        uint256 deltaExposureUpperAssetToAsset
    ) public {
        // Given: "exposureAsset" is smaller or equal as "exposureAssetMax" (test-case).
        assetState.exposureAssetLast = uint128(bound(assetState.exposureAssetLast, 0, type(uint128).max - 1));
        deltaExposureUpperAssetToAsset =
            bound(deltaExposureUpperAssetToAsset, 1, type(uint128).max - assetState.exposureAssetLast);
        uint256 expectedExposure = assetState.exposureAssetLast + deltaExposureUpperAssetToAsset;
        assetState.exposureAssetMax = uint128(bound(assetState.exposureAssetMax, expectedExposure, type(uint128).max));

        // And: State is persisted.
        setPrimaryAssetModuleAssetState(assetState);

        // When: Asset is indirectly withdrawn.
        vm.prank(address(mainRegistryExtension));
        (bool primaryFlag, uint256 usdExposureUpperAssetToAsset) = assetModule.processIndirectWithdrawal(
            assetState.creditor,
            assetState.asset,
            assetState.assetId,
            exposureUpperAssetToAsset,
            int256(deltaExposureUpperAssetToAsset)
        );

        // Then: Correct output variables are returned.
        assertTrue(primaryFlag);
        assertEq(usdExposureUpperAssetToAsset, assetState.usdExposureUpperAssetToAsset);

        // And: assetExposure is updated.
        bytes32 assetKey = bytes32(abi.encodePacked(assetState.assetId, assetState.asset));
        (uint128 actualExposure,,,) = assetModule.riskParams(assetState.creditor, assetKey);
        assertEq(actualExposure, expectedExposure);
    }

    function testFuzz_Success_processIndirectWithdrawal_negativeDeltaWithAbsoluteValueSmallerThanExposure(
        PrimaryAssetModuleAssetState memory assetState,
        uint256 exposureUpperAssetToAsset,
        uint256 deltaExposureUpperAssetToAsset
    ) public {
        // Given: deltaExposure is smaller or equal as assetState.exposureAssetLast.
        deltaExposureUpperAssetToAsset = bound(deltaExposureUpperAssetToAsset, 0, assetState.exposureAssetLast);
        uint256 expectedExposure = assetState.exposureAssetLast - deltaExposureUpperAssetToAsset;

        // And: State is persisted.
        setPrimaryAssetModuleAssetState(assetState);

        // When: Asset is indirectly withdrawn.
        vm.prank(address(mainRegistryExtension));
        (bool primaryFlag, uint256 usdExposureUpperAssetToAsset) = assetModule.processIndirectWithdrawal(
            assetState.creditor,
            assetState.asset,
            assetState.assetId,
            exposureUpperAssetToAsset,
            -int256(deltaExposureUpperAssetToAsset)
        );

        // Then: Correct output variables are returned.
        assertTrue(primaryFlag);
        assertEq(usdExposureUpperAssetToAsset, assetState.usdExposureUpperAssetToAsset);

        // And: assetExposure is updated.
        bytes32 assetKey = bytes32(abi.encodePacked(assetState.assetId, assetState.asset));
        (uint128 actualExposure,,,) = assetModule.riskParams(assetState.creditor, assetKey);
        assertEq(actualExposure, expectedExposure);
    }

    function testFuzz_Success_processIndirectWithdrawal_negativeDeltaGreaterThanExposure(
        PrimaryAssetModuleAssetState memory assetState,
        uint256 exposureUpperAssetToAsset,
        uint256 deltaExposureUpperAssetToAsset
    ) public {
        // Given: deltaExposure is bigger or equal as assetState.exposureAssetLast.
        deltaExposureUpperAssetToAsset = bound(deltaExposureUpperAssetToAsset, assetState.exposureAssetLast, INT256_MIN);

        // And: State is persisted.
        setPrimaryAssetModuleAssetState(assetState);

        // When: Asset is indirectly withdrawn.
        vm.prank(address(mainRegistryExtension));
        (bool primaryFlag, uint256 usdExposureUpperAssetToAsset) = assetModule.processIndirectWithdrawal(
            assetState.creditor,
            assetState.asset,
            assetState.assetId,
            exposureUpperAssetToAsset,
            -int256(deltaExposureUpperAssetToAsset)
        );

        // Then: Correct output variables are returned.
        assertTrue(primaryFlag);
        assertEq(usdExposureUpperAssetToAsset, assetState.usdExposureUpperAssetToAsset);

        // And: assetExposure is updated.
        bytes32 assetKey = bytes32(abi.encodePacked(assetState.assetId, assetState.asset));
        (uint128 actualExposure,,,) = assetModule.riskParams(assetState.creditor, assetKey);
        assertEq(actualExposure, 0);
    }
}