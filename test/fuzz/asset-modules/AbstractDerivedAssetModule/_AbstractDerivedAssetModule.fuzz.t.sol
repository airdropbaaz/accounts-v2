/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

import { Fuzz_Test, Constants } from "../../Fuzz.t.sol";

import { AssetModule } from "../../../../src/asset-modules/AbstractAssetModule.sol";
import { DerivedAssetModuleMock } from "../../../utils/mocks/DerivedAssetModuleMock.sol";
import { PrimaryAssetModuleMock } from "../../../utils/mocks/PrimaryAssetModuleMock.sol";

/**
 * @notice Common logic needed by all "DerivedAssetModule" fuzz tests.
 */
abstract contract AbstractDerivedAssetModule_Fuzz_Test is Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    struct DerivedAssetModuleProtocolState {
        uint128 lastUsdExposureProtocol;
        uint128 maxUsdExposureProtocol;
    }

    struct DerivedAssetModuleAssetState {
        address creditor;
        address asset;
        uint256 assetId;
        uint128 exposureAssetLast;
        uint128 lastUsdExposureAsset;
        address underlyingAsset;
        uint256 underlyingAssetId;
        uint256 exposureAssetToUnderlyingAsset;
        uint128 lastExposureAssetToUnderlyingAsset;
    }

    struct UnderlyingAssetModuleState {
        uint128 exposureAssetLast;
        uint256 usdValue;
    }

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    DerivedAssetModuleMock internal derivedAssetModule;
    PrimaryAssetModuleMock internal primaryAssetModule;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();

        vm.startPrank(users.creatorAddress);

        derivedAssetModule = new DerivedAssetModuleMock(address(mainRegistryExtension), 0);

        primaryAssetModule = new PrimaryAssetModuleMock(address(mainRegistryExtension), 0);

        mainRegistryExtension.addAssetModule(address(derivedAssetModule));
        mainRegistryExtension.addAssetModule(address(primaryAssetModule));

        // We assume conversion rate and price of underlying asset both equal to 1.
        // Conversion rate and prices of underlying assets will be tested in specific asset modules.
        derivedAssetModule.setUnderlyingAssetsAmount(1e18);

        vm.stopPrank();
    }

    /* ///////////////////////////////////////////////////////////////
                          HELPER FUNCTIONS
    /////////////////////////////////////////////////////////////// */
    function setDerivedAssetModuleProtocolState(DerivedAssetModuleProtocolState memory protocolState, address creditor)
        internal
    {
        derivedAssetModule.setUsdExposureProtocol(
            creditor, protocolState.maxUsdExposureProtocol, protocolState.lastUsdExposureProtocol
        );
    }

    function setDerivedAssetModuleAssetState(DerivedAssetModuleAssetState memory assetState) internal {
        address[] memory underlyingAssets = new address[](1);
        underlyingAssets[0] = assetState.underlyingAsset;
        uint256[] memory underlyingAssetIds = new uint256[](1);
        underlyingAssetIds[0] = assetState.underlyingAssetId;
        derivedAssetModule.addAsset(assetState.asset, assetState.assetId, underlyingAssets, underlyingAssetIds);

        derivedAssetModule.setUnderlyingAssetsAmount(assetState.exposureAssetToUnderlyingAsset);

        derivedAssetModule.setAssetInformation(
            assetState.creditor,
            assetState.asset,
            assetState.assetId,
            assetState.underlyingAsset,
            assetState.underlyingAssetId,
            assetState.exposureAssetLast,
            assetState.lastUsdExposureAsset,
            assetState.lastExposureAssetToUnderlyingAsset
        );
    }

    function setUnderlyingAssetModuleState(
        DerivedAssetModuleAssetState memory assetState,
        UnderlyingAssetModuleState memory underlyingPMState
    ) internal {
        // Set mapping between underlying Asset and its asset module in the Main Registry.
        mainRegistryExtension.setAssetModuleForAsset(assetState.underlyingAsset, address(primaryAssetModule));

        // Set max exposure of mocked Asset Module for Underlying assets.
        primaryAssetModule.setExposure(
            assetState.creditor, assetState.underlyingAsset, assetState.underlyingAssetId, 0, type(uint128).max
        );

        // Mock the "usdValue".
        primaryAssetModule.setUsdValue(underlyingPMState.usdValue);
    }

    function givenValidState(
        DerivedAssetModuleProtocolState memory protocolState,
        DerivedAssetModuleAssetState memory assetState,
        UnderlyingAssetModuleState memory underlyingPMState
    )
        internal
        view
        returns (
            DerivedAssetModuleProtocolState memory,
            DerivedAssetModuleAssetState memory,
            UnderlyingAssetModuleState memory
        )
    {
        // Given: id's are smaller or equal to type(uint96).max.
        assetState.assetId = bound(assetState.assetId, 0, type(uint96).max);
        assetState.underlyingAssetId = bound(assetState.underlyingAssetId, 0, type(uint96).max);

        // And: usd Value of protocol is bigger or equal to each individual usd value of an asset (Invariant).
        assetState.lastUsdExposureAsset =
            uint128(bound(assetState.lastUsdExposureAsset, 0, protocolState.lastUsdExposureProtocol));

        return (protocolState, assetState, underlyingPMState);
    }

    function givenNonRevertingWithdrawal(
        DerivedAssetModuleProtocolState memory protocolState,
        DerivedAssetModuleAssetState memory assetState,
        UnderlyingAssetModuleState memory underlyingPMState,
        uint256 exposureUpperAssetToAsset,
        int256 deltaExposureUpperAssetToAsset
    )
        internal
        view
        returns (
            DerivedAssetModuleProtocolState memory,
            DerivedAssetModuleAssetState memory,
            UnderlyingAssetModuleState memory,
            uint256,
            int256
        )
    {
        // Given: "usdExposureToUnderlyingAsset" does not overflow.
        underlyingPMState.usdValue = bound(underlyingPMState.usdValue, 0, type(uint128).max);

        // And: "usdExposureUpperAssetToAsset" does not overflow (unrealistic big values).
        if (underlyingPMState.usdValue != 0) {
            exposureUpperAssetToAsset =
                bound(exposureUpperAssetToAsset, 0, type(uint256).max / underlyingPMState.usdValue);
        }

        // And: id's are smaller or equal to type(uint96).max.
        assetState.assetId = bound(assetState.assetId, 0, type(uint96).max);
        assetState.underlyingAssetId = bound(assetState.underlyingAssetId, 0, type(uint96).max);

        // Calculate exposureAsset.
        uint256 exposureAsset;
        if (deltaExposureUpperAssetToAsset > 0) {
            // Given: No overflow on exposureAsset.
            deltaExposureUpperAssetToAsset = int256(
                bound(uint256(deltaExposureUpperAssetToAsset), 0, type(uint128).max - assetState.exposureAssetLast)
            );

            exposureAsset = assetState.exposureAssetLast + uint256(deltaExposureUpperAssetToAsset);
        } else {
            // And: No overflow on negation most negative int256 (this overflows).
            vm.assume(deltaExposureUpperAssetToAsset > type(int256).min);

            if (uint256(-deltaExposureUpperAssetToAsset) < assetState.exposureAssetLast) {
                exposureAsset = uint256(assetState.exposureAssetLast) - uint256(-deltaExposureUpperAssetToAsset);
            }
        }

        // And: No overflow on exposureAssetToUnderlyingAsset.
        assetState.exposureAssetToUnderlyingAsset =
            bound(assetState.exposureAssetToUnderlyingAsset, 0, type(uint128).max);

        if (underlyingPMState.usdValue >= assetState.lastUsdExposureAsset) {
            // And: "usdExposureProtocol" does not overflow (unrealistically big).
            protocolState.lastUsdExposureProtocol = uint128(
                bound(
                    protocolState.lastUsdExposureProtocol,
                    assetState.lastUsdExposureAsset,
                    type(uint128).max - (underlyingPMState.usdValue - assetState.lastUsdExposureAsset)
                )
            );
        }

        return (protocolState, assetState, underlyingPMState, exposureUpperAssetToAsset, deltaExposureUpperAssetToAsset);
    }

    function givenNonRevertingDeposit(
        DerivedAssetModuleProtocolState memory protocolState,
        DerivedAssetModuleAssetState memory assetState,
        UnderlyingAssetModuleState memory underlyingPMState,
        uint256 exposureUpperAssetToAsset,
        int256 deltaExposureUpperAssetToAsset
    )
        internal
        view
        returns (
            DerivedAssetModuleProtocolState memory,
            DerivedAssetModuleAssetState memory,
            UnderlyingAssetModuleState memory,
            uint256,
            int256
        )
    {
        // Identical bounds as for Withdrawals.
        (protocolState, assetState, underlyingPMState, exposureUpperAssetToAsset, deltaExposureUpperAssetToAsset) =
        givenNonRevertingWithdrawal(
            protocolState, assetState, underlyingPMState, exposureUpperAssetToAsset, deltaExposureUpperAssetToAsset
        );

        // And: exposure does not exceeds max exposure.
        uint256 usdExposureProtocolExpected;
        if (underlyingPMState.usdValue >= assetState.lastUsdExposureAsset) {
            usdExposureProtocolExpected =
                protocolState.lastUsdExposureProtocol + (underlyingPMState.usdValue - assetState.lastUsdExposureAsset);
        } else {
            usdExposureProtocolExpected = protocolState.lastUsdExposureProtocol
                > assetState.lastUsdExposureAsset - underlyingPMState.usdValue
                ? protocolState.lastUsdExposureProtocol - (assetState.lastUsdExposureAsset - underlyingPMState.usdValue)
                : 0;
        }
        protocolState.maxUsdExposureProtocol =
            uint128(bound(protocolState.maxUsdExposureProtocol, usdExposureProtocolExpected, type(uint128).max));

        return (protocolState, assetState, underlyingPMState, exposureUpperAssetToAsset, deltaExposureUpperAssetToAsset);
    }
}
