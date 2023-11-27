/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

/**
 * @title Creditor implementation.
 * @author Pragma Labs
 * @notice This contract contains the minimum functionality a Creditor, interacting with Arcadia Accounts, needs to implement.
 * @dev For the implementation of Arcadia Accounts, see: https://github.com/arcadia-finance/accounts-v2.
 */
interface ICreditor {
    /**
     * @notice Checks if Account fulfills all requirements and returns Creditor parameters.
     * @param accountVersion The version of the Arcadia Account.
     * @return success Bool indicating if all requirements are met.
     * @return numeraire The Numeraire of the Creditor.
     * @return liquidator The liquidator of the Creditor.
     * @return fixedLiquidationCost Estimated fixed costs (independent of size of debt) to liquidate a position.
     */
    function openMarginAccount(uint256 accountVersion) external returns (bool, address, address, uint256);

    /**
     * @notice Checks if Account can be closed.
     * @param account The Account address.
     */
    function closeMarginAccount(address account) external;

    /**
     * @notice Returns the open position of the Account.
     * @param account The Account address.
     * @return openPosition The open position of the Account.
     */
    function getOpenPosition(address account) external view returns (uint256);

    /**
     * @notice Returns the Risk Manager of the creditor.
     * @return riskManager The Risk Manager of the creditor.
     */
    function riskManager() external view returns (address riskManager);

    /**
     * @notice Starts the liquidation of an account and returns the open position of the Account.
     * @param initiator The address of the liquidation initiator.
     * @return openPosition the open position of the Account.
     */
    function startLiquidation(address initiator) external returns (uint256);
}
