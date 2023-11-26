/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Fuzz_Test } from "../../Fuzz.t.sol";

import { MultiActionMock } from "../../../utils/mocks/MultiActionMock.sol";
import { MultiCallExtention } from "../../../utils/Extensions.sol";

/**
 * @notice Common logic needed by all "MultiCall" fuzz tests.
 */
abstract contract MultiCall_Fuzz_Test is Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */
    error LengthMismatch();
    error InsufficientAmountOut();
    error OnlyInternal();
    error LeftoverNfts();

    /* ///////////////////////////////////////////////////////////////
                             VARIABLES
    /////////////////////////////////////////////////////////////// */

    uint256 internal numberStored;

    /* ///////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    MultiCallExtention internal action;
    MultiActionMock internal multiActionMock;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        action = new MultiCallExtention();
    }

    /* ///////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    /////////////////////////////////////////////////////////////// */
    function setNumberStored(uint256 number) public {
        numberStored = number;
    }
}
