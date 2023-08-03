/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.13;

interface IVault {
    /**
     * @notice Returns the Vault version.
     * @return version The Vault version.
     */
    function vaultVersion() external view returns (uint16);

    /**
     * @notice Initiates the variables of the vault.
     * @param owner The sender of the 'createVault' on the factory
     * @param registry The 'beacon' contract with the external logic.
     * @param vaultVersion The version of the vault logic.
     * @param baseCurrency The Base-currency in which the vault is denominated.
     */
    function initialize(address owner, address registry, uint16 vaultVersion, address baseCurrency) external;

    /**
     * @notice Updates the vault version and stores a new address in the EIP1967 implementation slot.
     * @param newImplementation The contract with the new vault logic.
     * @param newRegistry The MainRegistry for this specific implementation (might be identical as the old registry).
     * @param data Arbitrary data, can contain instructions to execute when updating Vault to new logic.
     * @param newVersion The new version of the vault logic.
     */
    function upgradeVault(address newImplementation, address newRegistry, uint16 newVersion, bytes calldata data)
        external;

    /**
     * @notice Transfers ownership of the contract to a new account.
     * @param newOwner The new owner of the Vault.
     */
    function transferOwnership(address newOwner) external;
}
