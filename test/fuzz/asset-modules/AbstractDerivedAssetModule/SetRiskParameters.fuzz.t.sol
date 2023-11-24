/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

import { AbstractDerivedAssetModule_Fuzz_Test, AssetModule } from "./_AbstractDerivedAssetModule.fuzz.t.sol";

import { DerivedAssetModule } from "../../../../src/asset-modules/AbstractDerivedAssetModule.sol";
import { AssetValuationLib, AssetValueAndRiskFactors } from "../../../../src/libraries/AssetValuationLib.sol";

/**
 * @notice Fuzz tests for the function "setRiskParameters" of contract "AbstractDerivedAssetModule".
 */
contract SetRiskParameters_AbstractDerivedAssetModule_Fuzz_Test is AbstractDerivedAssetModule_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        AbstractDerivedAssetModule_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_setRiskParameters_NonRegistry(
        address unprivilegedAddress_,
        address creditor,
        uint112 maxExposureInUsd,
        uint16 riskFactor
    ) public {
        vm.assume(unprivilegedAddress_ != address(registryExtension));

        vm.startPrank(unprivilegedAddress_);
        vm.expectRevert(AssetModule.OnlyRegistry.selector);
        derivedAssetModule.setRiskParameters(creditor, maxExposureInUsd, riskFactor);
        vm.stopPrank();
    }

    function testFuzz_Revert_setRiskParameters_RiskFactorNotInLimits(
        address creditor,
        uint112 maxExposureInUsd,
        uint16 riskFactor
    ) public {
        riskFactor = uint16(bound(riskFactor, AssetValuationLib.ONE_4 + 1, type(uint16).max));

        vm.startPrank(address(registryExtension));
        vm.expectRevert(DerivedAssetModule.RiskFactorNotInLimits.selector);
        derivedAssetModule.setRiskParameters(creditor, maxExposureInUsd, riskFactor);
        vm.stopPrank();
    }

    function testFuzz_Success_setRiskParameters(address creditor, uint112 maxExposureInUsd, uint16 riskFactor) public {
        riskFactor = uint16(bound(riskFactor, 0, AssetValuationLib.ONE_4));

        vm.prank(address(registryExtension));
        derivedAssetModule.setRiskParameters(creditor, maxExposureInUsd, riskFactor);

        (, uint128 actualMaxExposureInUsd, uint16 actualRiskFactor) = derivedAssetModule.riskParams(creditor);
        assertEq(actualMaxExposureInUsd, maxExposureInUsd);
        assertEq(actualRiskFactor, riskFactor);
    }
}
