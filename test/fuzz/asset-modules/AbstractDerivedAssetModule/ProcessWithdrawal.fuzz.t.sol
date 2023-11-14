/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

import { AbstractDerivedAssetModule_Fuzz_Test } from "./_AbstractDerivedAssetModule.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_processWithdrawal" of contract "AbstractDerivedAssetModule".
 */
contract ProcessWithdrawal_AbstractDerivedAssetModule_Fuzz_Test is AbstractDerivedAssetModule_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        AbstractDerivedAssetModule_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_processWithdrawal_PositiveDeltaUsdExposure_Overflow(
        DerivedAssetModuleProtocolState memory protocolState,
        DerivedAssetModuleAssetState memory assetState,
        UnderlyingAssetModuleState memory underlyingPMState,
        uint256 exposureAsset
    ) public {
        // Given: valid initial state.
        (protocolState, assetState, underlyingPMState) = givenValidState(protocolState, assetState, underlyingPMState);

        // And: No overflow on exposureAssetToUnderlyingAsset.
        assetState.exposureAssetToUnderlyingAsset =
            bound(assetState.exposureAssetToUnderlyingAsset, 0, type(uint128).max);

        // And: delta "usdExposureAsset" is positive (test-case).
        vm.assume(assetState.lastUsdExposureAsset < type(uint128).max);
        underlyingPMState.usdValue =
            bound(underlyingPMState.usdValue, assetState.lastUsdExposureAsset + 1, type(uint128).max);

        // And: "usdExposureProtocol" overflows (unrealistically big).
        protocolState.lastUsdExposureProtocol = uint128(
            bound(
                protocolState.lastUsdExposureProtocol,
                type(uint128).max - (underlyingPMState.usdValue - assetState.lastUsdExposureAsset) + 1,
                type(uint128).max
            )
        );

        // And: State is persisted.
        setDerivedAssetModuleProtocolState(protocolState, assetState.creditor);
        setDerivedAssetModuleAssetState(assetState);
        setUnderlyingAssetModuleState(assetState, underlyingPMState);

        // When: "_processWithdrawal" is called.
        // Then: The transaction reverts with "ADAM_PW: Overflow".
        bytes32 assetKey = derivedAssetModule.getKeyFromAsset(assetState.asset, assetState.assetId);
        vm.expectRevert("ADAM_PW: Overflow");
        derivedAssetModule.processWithdrawal(assetState.creditor, assetKey, exposureAsset);
    }

    function testFuzz_Success_processWithdrawal_PositiveDeltaUsdExposure(
        DerivedAssetModuleProtocolState memory protocolState,
        DerivedAssetModuleAssetState memory assetState,
        UnderlyingAssetModuleState memory underlyingPMState,
        uint256 exposureAsset
    ) public {
        // Given: valid initial state.
        (protocolState, assetState, underlyingPMState) = givenValidState(protocolState, assetState, underlyingPMState);

        // And: No overflow on exposureAssetToUnderlyingAsset.
        assetState.exposureAssetToUnderlyingAsset =
            bound(assetState.exposureAssetToUnderlyingAsset, 0, type(uint128).max);

        // And: delta "usdExposureAsset" is positive (test-case).
        underlyingPMState.usdValue =
            bound(underlyingPMState.usdValue, assetState.lastUsdExposureAsset, type(uint128).max);

        // And: "usdExposureProtocol" does not overflow (unrealistically big).
        protocolState.lastUsdExposureProtocol = uint128(
            bound(
                protocolState.lastUsdExposureProtocol,
                assetState.lastUsdExposureAsset,
                type(uint128).max - (underlyingPMState.usdValue - assetState.lastUsdExposureAsset)
            )
        );
        uint256 usdExposureProtocolExpected =
            protocolState.lastUsdExposureProtocol + (underlyingPMState.usdValue - assetState.lastUsdExposureAsset);

        // And: exposure does not exceeds max exposure.
        protocolState.maxUsdExposureProtocol =
            uint128(bound(protocolState.maxUsdExposureProtocol, usdExposureProtocolExpected, type(uint128).max));

        // And: State is persisted.
        setDerivedAssetModuleProtocolState(protocolState, assetState.creditor);
        setDerivedAssetModuleAssetState(assetState);
        setUnderlyingAssetModuleState(assetState, underlyingPMState);

        // And: Underlying Asset is properly added to an underlying Asset Module.
        int256 deltaExposureAssetToUnderlyingAsset = int256(assetState.exposureAssetToUnderlyingAsset)
            - int256(uint256(assetState.lastExposureAssetToUnderlyingAsset));
        bytes memory data = abi.encodeCall(
            mainRegistryExtension.getUsdValueExposureToUnderlyingAssetAfterWithdrawal,
            (
                assetState.creditor,
                assetState.underlyingAsset,
                assetState.underlyingAssetId,
                assetState.exposureAssetToUnderlyingAsset,
                deltaExposureAssetToUnderlyingAsset
            )
        );

        // When: "_processDeposit" is called.
        // Then: The Function "getUsdValueExposureToUnderlyingAssetAfterWithdrawal" on "MainRegistry" is called with correct parameters.
        vm.expectCall(address(mainRegistryExtension), data);
        bytes32 assetKey = derivedAssetModule.getKeyFromAsset(assetState.asset, assetState.assetId);
        uint256 usdExposureAsset = derivedAssetModule.processWithdrawal(assetState.creditor, assetKey, exposureAsset);

        // Then: Transaction returns correct "usdExposureAsset".
        assertEq(usdExposureAsset, underlyingPMState.usdValue);

        // And: "lastExposureAssetToUnderlyingAsset" is updated.
        bytes32 UnderlyingAssetKey =
            derivedAssetModule.getKeyFromAsset(assetState.underlyingAsset, assetState.underlyingAssetId);
        assertEq(
            derivedAssetModule.getExposureAssetToUnderlyingAssetsLast(assetState.creditor, assetKey, UnderlyingAssetKey),
            assetState.exposureAssetToUnderlyingAsset
        );

        // And: "lastUsdExposureAsset" is updated.
        (, uint256 lastUsdExposureAsset) = derivedAssetModule.getAssetExposureLast(assetState.creditor, assetKey);
        assertEq(lastUsdExposureAsset, underlyingPMState.usdValue);

        // And: "usdExposureProtocol" is updated.
        (uint128 usdExposureProtocolActual,,) = derivedAssetModule.riskParams(assetState.creditor);
        assertEq(usdExposureProtocolActual, usdExposureProtocolExpected);
    }

    function testFuzz_Success_processWithdrawal_NegativeDeltaUsdExposure_NoUnderflow(
        DerivedAssetModuleProtocolState memory protocolState,
        DerivedAssetModuleAssetState memory assetState,
        UnderlyingAssetModuleState memory underlyingPMState,
        uint256 exposureAsset
    ) public {
        // Given: valid initial state.
        (protocolState, assetState, underlyingPMState) = givenValidState(protocolState, assetState, underlyingPMState);

        // And: No overflow on exposureAssetToUnderlyingAsset.
        assetState.exposureAssetToUnderlyingAsset =
            bound(assetState.exposureAssetToUnderlyingAsset, 0, type(uint128).max);

        // And: delta "usdExposureAsset" is negative (test-case).
        vm.assume(assetState.lastUsdExposureAsset > 0);
        underlyingPMState.usdValue = bound(underlyingPMState.usdValue, 0, assetState.lastUsdExposureAsset - 1);

        // And: "usdExposureProtocol" does not underflow (test-case).
        protocolState.lastUsdExposureProtocol = uint128(
            bound(
                protocolState.lastUsdExposureProtocol,
                assetState.lastUsdExposureAsset - underlyingPMState.usdValue,
                type(uint128).max
            )
        );
        uint256 usdExposureProtocolExpected =
            protocolState.lastUsdExposureProtocol - (assetState.lastUsdExposureAsset - underlyingPMState.usdValue);

        // And: State is persisted.
        setDerivedAssetModuleProtocolState(protocolState, assetState.creditor);
        setDerivedAssetModuleAssetState(assetState);
        setUnderlyingAssetModuleState(assetState, underlyingPMState);

        // And: Underlying Asset is properly added to an underlying Asset Module.
        int256 deltaExposureAssetToUnderlyingAsset = int256(assetState.exposureAssetToUnderlyingAsset)
            - int256(uint256(assetState.lastExposureAssetToUnderlyingAsset));
        bytes memory data = abi.encodeCall(
            mainRegistryExtension.getUsdValueExposureToUnderlyingAssetAfterWithdrawal,
            (
                assetState.creditor,
                assetState.underlyingAsset,
                assetState.underlyingAssetId,
                assetState.exposureAssetToUnderlyingAsset,
                deltaExposureAssetToUnderlyingAsset
            )
        );

        // When: "_processDeposit" is called.
        // Then: The Function "getUsdValueExposureToUnderlyingAssetAfterWithdrawal" on "MainRegistry" is called with correct parameters.
        vm.expectCall(address(mainRegistryExtension), data);
        bytes32 assetKey = derivedAssetModule.getKeyFromAsset(assetState.asset, assetState.assetId);
        uint256 usdExposureAsset = derivedAssetModule.processWithdrawal(assetState.creditor, assetKey, exposureAsset);

        // Then: Transaction returns correct "usdExposureAsset".
        assertEq(usdExposureAsset, underlyingPMState.usdValue);

        // And: "lastExposureAssetToUnderlyingAsset" is updated.
        bytes32 UnderlyingAssetKey =
            derivedAssetModule.getKeyFromAsset(assetState.underlyingAsset, assetState.underlyingAssetId);
        assertEq(
            derivedAssetModule.getExposureAssetToUnderlyingAssetsLast(assetState.creditor, assetKey, UnderlyingAssetKey),
            assetState.exposureAssetToUnderlyingAsset
        );

        // And: "lastUsdExposureAsset" is updated.
        (, uint256 lastUsdExposureAsset) = derivedAssetModule.getAssetExposureLast(assetState.creditor, assetKey);
        assertEq(lastUsdExposureAsset, underlyingPMState.usdValue);

        // And: "usdExposureProtocol" is updated.
        (uint128 usdExposureProtocolActual,,) = derivedAssetModule.riskParams(assetState.creditor);
        assertEq(usdExposureProtocolActual, usdExposureProtocolExpected);
    }

    function testFuzz_Success_processWithdrawal_NegativeDeltaUsdExposure_Underflow(
        DerivedAssetModuleProtocolState memory protocolState,
        DerivedAssetModuleAssetState memory assetState,
        UnderlyingAssetModuleState memory underlyingPMState,
        uint256 exposureAsset
    ) public {
        // Given: valid initial state.
        (protocolState, assetState, underlyingPMState) = givenValidState(protocolState, assetState, underlyingPMState);

        // And: No overflow on exposureAssetToUnderlyingAsset.
        assetState.exposureAssetToUnderlyingAsset =
            bound(assetState.exposureAssetToUnderlyingAsset, 0, type(uint128).max);

        // And: delta "usdExposureAsset" is negative (test-case).
        vm.assume(assetState.lastUsdExposureAsset > 0);
        underlyingPMState.usdValue = bound(underlyingPMState.usdValue, 0, assetState.lastUsdExposureAsset - 1);

        // And: "usdExposureProtocol" does underflow (test-case).
        protocolState.lastUsdExposureProtocol = uint128(
            bound(
                protocolState.lastUsdExposureProtocol, 0, assetState.lastUsdExposureAsset - underlyingPMState.usdValue
            )
        );

        // And: State is persisted.
        setDerivedAssetModuleProtocolState(protocolState, assetState.creditor);
        setDerivedAssetModuleAssetState(assetState);
        setUnderlyingAssetModuleState(assetState, underlyingPMState);

        // And: Underlying Asset is properly added to an underlying Asset Module.
        int256 deltaExposureAssetToUnderlyingAsset = int256(assetState.exposureAssetToUnderlyingAsset)
            - int256(uint256(assetState.lastExposureAssetToUnderlyingAsset));
        bytes memory data = abi.encodeCall(
            mainRegistryExtension.getUsdValueExposureToUnderlyingAssetAfterWithdrawal,
            (
                assetState.creditor,
                assetState.underlyingAsset,
                assetState.underlyingAssetId,
                assetState.exposureAssetToUnderlyingAsset,
                deltaExposureAssetToUnderlyingAsset
            )
        );

        // When: "_processDeposit" is called.
        // Then: The Function "getUsdValueExposureToUnderlyingAssetAfterWithdrawal" on "MainRegistry" is called with correct parameters.
        vm.expectCall(address(mainRegistryExtension), data);
        bytes32 assetKey = derivedAssetModule.getKeyFromAsset(assetState.asset, assetState.assetId);
        uint256 usdExposureAsset = derivedAssetModule.processWithdrawal(assetState.creditor, assetKey, exposureAsset);

        // Then: Transaction returns correct "usdExposureAsset".
        assertEq(usdExposureAsset, underlyingPMState.usdValue);

        // And: "lastExposureAssetToUnderlyingAsset" is updated.
        bytes32 UnderlyingAssetKey =
            derivedAssetModule.getKeyFromAsset(assetState.underlyingAsset, assetState.underlyingAssetId);
        assertEq(
            derivedAssetModule.getExposureAssetToUnderlyingAssetsLast(assetState.creditor, assetKey, UnderlyingAssetKey),
            assetState.exposureAssetToUnderlyingAsset
        );

        // And: "lastUsdExposureAsset" is updated.
        (, uint256 lastUsdExposureAsset) = derivedAssetModule.getAssetExposureLast(assetState.creditor, assetKey);
        assertEq(lastUsdExposureAsset, underlyingPMState.usdValue);

        // And: "usdExposureProtocol" is updated.
        (uint128 usdExposureProtocolActual,,) = derivedAssetModule.riskParams(assetState.creditor);
        assertEq(usdExposureProtocolActual, 0);
    }
}