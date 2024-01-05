/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Fuzz_Test, Constants } from "../../Fuzz.t.sol";

import { StakingModule } from "../../../../src/asset-modules/staking-module/AbstractStakingModule.sol";
import { StakingModuleMock } from "../../../utils/mocks/StakingModuleMock.sol";
import { ERC20Mock } from "../../../utils/mocks/ERC20Mock.sol";

/**
 * @notice Common logic needed by "StakingModule" fuzz tests.
 */
abstract contract AbstractStakingModule_Fuzz_Test is Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    struct StakingModuleStateForAsset {
        uint128 currentRewardGlobal;
        uint128 lastRewardPerTokenGlobal;
        uint128 lastRewardGlobal;
        uint128 totalStaked;
        uint128 amountStakedForId;
    }

    struct StakingModuleStateForPosition {
        address asset;
        uint128 amountStaked;
        uint128 lastRewardPerTokenPosition;
        uint128 lastRewardPosition;
    }

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    StakingModuleMock internal stakingModule;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();

        vm.startPrank(users.creatorAddress);

        stakingModule = new StakingModuleMock();

        vm.stopPrank();
    }

    /* ///////////////////////////////////////////////////////////////
                          HELPER FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    function setStakingModuleState(
        StakingModuleStateForAsset memory stakingModuleStateForAsset,
        StakingModuleStateForPosition memory stakingModuleStateForPosition,
        address asset,
        uint256 id
    )
        internal
        returns (
            StakingModuleStateForId memory stakingModuleStateForAsset_,
            StakingModuleStateForPosition memory stakingModuleStateForPosition_
        )
    {
        (stakingModuleStateForAsset_, stakingModuleStateForPosition_) =
            givenValidStakingModuleState(stakingModuleStateForAsset, stakingModuleStateForPosition);

        stakingModule.setLastRewardGlobal(asset, stakingModuleState_.lastRewardGlobal);
        stakingModule.setTotalStaked(asset, stakingModuleState_.totalStaked);
        stakingModule.setLastRewardPosition(asset, stakingModuleState_.lastRewardPosition, account);
        stakingModule.setLastRewardPerTokenPosition(asset, stakingModuleState_.lastRewardPerTokenPosition, account);
        stakingModule.setLastRewardPerTokenGlobal(asset, stakingModuleState_.lastRewardPerTokenGlobal);
        stakingModule.setActualRewardBalance(asset, stakingModuleState_.currentRewardGlobal);
        stakingModule.setAmountStakedForPosition(asset, stakingModuleState_.amountStakedForId);
    }

    function givenValidStakingModuleState(
        StakingModuleStateForAsset memory stakingModuleStateForAsset,
        StakingModuleStateForPosition memory stakingModuleStateForPosition
    )
        public
        view
        returns (
            StakingModuleStateForAsset memory stakingModuleStateForAsset_,
            StakingModuleStateForPosition memory stakingModuleStateForPosition_
        )
    {
        // Given : Actual reward balance should be at least equal to lastRewardGlobal.
        vm.assume(stakingModuleStateForAsset.currentRewardGlobal >= stakingModuleStateForAsset.lastRewardGlobal);

        // Given : The difference between the actual and previous reward balance should be smaller than type(uint128).max / 1e18.
        vm.assume(
            stakingModuleStateForAsset.currentRewardGlobal - stakingModuleStateForAsset.lastRewardGlobal
                < type(uint128).max / 1e18
        );

        // Given : lastRewardPerTokenGlobal + rewardPerTokenClaimable should not be over type(uint128).max
        stakingModuleStateForAsset.lastRewardPerTokenGlobal = uint128(
            bound(
                stakingModuleStateForAsset.lastRewardPerTokenGlobal,
                0,
                type(uint128).max
                    - (
                        (stakingModuleStateForAsset.currentRewardGlobal - stakingModuleStateForAsset.lastRewardGlobal)
                            * 1e18
                    )
            )
        );

        // Given : lastRewardPerTokenGlobal should always be >= lastRewardPerTokenPosition
        vm.assume(
            stakingModuleStateForAsset.lastRewardPerTokenGlobal
                >= stakingModuleStateForPosition.lastRewardPerTokenPosition
        );

        // Cache rewardPerTokenClaimable
        uint128 rewardPerTokenClaimable = stakingModuleStateForAsset.lastRewardPerTokenGlobal
            + ((stakingModuleStateForAsset.currentRewardGlobal - stakingModuleStateForAsset.lastRewardGlobal) * 1e18);

        // Given : amountStakedForId * rewardPerTokenClaimable should not be > type(uint128)
        stakingModuleState.amountStakedForId =
            uint128(bound(stakingModuleState.amountStakedForId, 0, (type(uint128).max) - rewardPerTokenClaimable));

        // Extra check for the above
        vm.assume(uint256(stakingModuleState.amountStakedForId) * rewardPerTokenClaimable < type(uint128).max);

        // Given : previously earned rewards for Account + new rewards should not be > type(uint128).max.
        stakingModuleState.lastRewardPosition = uint128(
            bound(
                stakingModuleState.lastRewardPosition,
                0,
                type(uint128).max - (stakingModuleState.amountStakedForId * rewardPerTokenClaimable)
            )
        );

        // Given : totalSupply should be >= to amountStakedForId
        stakingModuleState.totalSupply =
            uint128(bound(stakingModuleState.totalSupply, stakingModuleState.amountStakedForId, type(uint128).max));

        stakingModuleState_ = stakingModuleState;
    }

    function addStakingTokens(uint8 numberOfTokens, uint8 underlyingTokenDecimals, uint8 rewardTokenDecimals)
        public
        returns (address[] memory underlyingTokens, address[] memory rewardTokens)
    {
        underlyingTokens = new address[](numberOfTokens);
        rewardTokens = new address[](numberOfTokens);

        underlyingTokenDecimals = uint8(bound(underlyingTokenDecimals, 0, 18));
        rewardTokenDecimals = uint8(bound(rewardTokenDecimals, 0, 18));

        for (uint8 i = 0; i < numberOfTokens; ++i) {
            ERC20Mock underlyingToken = new ERC20Mock("UnderlyingToken", "UTK", underlyingTokenDecimals);
            ERC20Mock rewardToken = new ERC20Mock("RewardToken", "RWT", rewardTokenDecimals);

            underlyingTokens[i] = address(underlyingToken);
            rewardTokens[i] = address(rewardToken);

            stakingModule.addNewStakingToken(address(underlyingToken), address(rewardToken));
        }
    }
}
