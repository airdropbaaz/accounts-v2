/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.19;

interface IMainRegistry {
    /**
     * @notice Adds a new oracle to the Main Registry.
     * @return oracleId Unique identifier of the oracle.
     */
    function addOracle() external returns (uint256 oracleId);
}
