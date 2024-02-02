/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

import { StakedAerodromeAM_Fork_Test, StakedAerodromeAM } from "./_StakedAerodromeAM.fork.t.sol";

import { ERC20 } from "../../../../lib/solmate/src/tokens/ERC20.sol";
import { BitPackingLib } from "../../../../src/libraries/BitPackingLib.sol";
import { IAeroPool } from "../../../../src/asset-modules/Aerodrome-Finance/interfaces/IAeroPool.sol";

/**
 * @notice Fork tests for the "claimReward" function of contract "StakedAerodromeAM".
 */
contract ClaimReward_StakedAerodromeAM_Fork_Test is StakedAerodromeAM_Fork_Test {
    /*///////////////////////////////////////////////////////////////
                            SET-UP FUNCTION
    ///////////////////////////////////////////////////////////////*/

    function setUp() public override {
        StakedAerodromeAM_Fork_Test.setUp();
    }

    /*///////////////////////////////////////////////////////////////
                            FORK TESTS
    ///////////////////////////////////////////////////////////////*/

    function testFork_Success_ClaimReward() public {
        uint256 amount0 = 100_000 * 1e6;
        uint256 amount1 = 100_000 * 1e18;

        // Given : A user adds liquidity in an Aerodrome Pool
        uint256 lpBalance = addLiquidityUSDC(USDC, DAI, true, amount0, amount1, users.accountOwner, stablePool);

        // And : Add asset and gauge to the AM
        stakedAerodromeAM.addAsset(stablePool, stableGauge);

        // And : We transfer the LP to the AM (transfer done in the mint() which calls _stake())
        vm.startPrank(users.accountOwner);
        ERC20(stablePool).transfer(address(stakedAerodromeAM), lpBalance);

        // And : LP is staked via the stakedAerodromeAM
        stakedAerodromeAM.stake(stablePool, lpBalance);

        assertEq(stakedAerodromeAM.REWARD_TOKEN().balanceOf(address(stakedAerodromeAM)), 0);

        // And : We let rewards accumulate
        vm.warp(block.timestamp + 3 days);

        // When : Calling claimReward()
        stakedAerodromeAM.claimReward(stablePool);

        // Then : Rewards should have been claimed and received in the AM
        assertGt(stakedAerodromeAM.REWARD_TOKEN().balanceOf(address(stakedAerodromeAM)), 0);
    }
}
