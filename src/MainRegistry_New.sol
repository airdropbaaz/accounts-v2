/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

import { IChainLinkData } from "./interfaces/IChainLinkData.sol";
import { IFactory } from "./interfaces/IFactory.sol";
import { IPricingModule_New } from "./interfaces/IPricingModule_New.sol";
import { IMainRegistry } from "./interfaces/IMainRegistry_New.sol";
import { FixedPointMathLib } from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import { RiskModule } from "./RiskModule.sol";
import { MainRegistryGuardian } from "./guardians/MainRegistryGuardian.sol";

/**
 * @title Main Asset registry
 * @author Pragma Labs
 * @notice The Main Registry stores basic information for each token that can, or could at some point, be deposited in the Accounts.
 * @dev No end-user should directly interact with the Main Registry, only Accounts, Pricing Modules or the contract owner.
 */
contract MainRegistry_New is IMainRegistry, MainRegistryGuardian {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The contract address of the this contract,
    // used to prevent delegateCalls for certain functions.
    address immutable _this;
    // Counter for the number of baseCurrencies in use.
    uint256 public baseCurrencyCounter;
    // Contract address of the Factory.
    address public immutable factory;

    // Array with all the contract addresses of Pricing Modules.
    address[] public pricingModules;
    // Array with all the contract addresses of Tokens that can be Priced.
    address[] public assetsInMainRegistry;
    // Array with all the contract addresses of baseCurrencies.
    address[] public baseCurrencies;

    // Map mainRegistry => flag.
    mapping(address => bool) public inMainRegistry;
    // Map pricingModule => flag.
    mapping(address => bool) public isPricingModule;
    // Map baseCurrency => flag.
    mapping(address => bool) public isBaseCurrency;
    // Map action => flag.
    mapping(address => bool) public isActionAllowed;
    // Map baseCurrency => baseCurrencyIdentifier.
    mapping(address => uint256) public assetToBaseCurrency;
    // Map asset => assetInformation.
    mapping(address => AssetInformation) public assetToAssetInformation;
    // Map baseCurrencyIdentifier => baseCurrencyInformation.
    mapping(uint256 => BaseCurrencyInformation) public baseCurrencyToInformation;

    // Struct with additional information for a specific asset.
    struct AssetInformation {
        uint96 assetType; // Identifier for the token standard of the asset.
        address pricingModule; // Contract address of the module that can price the specific asset.
    }

    // Struct with additional information for a specific baseCurrency.
    struct BaseCurrencyInformation {
        uint64 baseCurrencyUnitCorrection; // The factor with which the baseCurrency should be multiplied to bring it to 18 decimals.
        address assetAddress; // The contract address of the baseCurrency.
        uint64 baseCurrencyToUsdOracleUnit; // The unit of the oracle, equal to 10^decimalsOracle.
        address baseCurrencyToUsdOracle; // The contract address of the pricing oracle for baseCurrency -> USD.
        bytes8 baseCurrencyLabel; // Human readable label.
    }

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event BaseCurrencyAdded(address indexed assetAddress, uint8 indexed baseCurrencyId, bytes8 label);
    event AllowedActionSet(address indexed action, bool allowed);
    event PricingModuleAdded(address pricingModule);
    event AssetAdded(address indexed assetAddress, address indexed pricingModule, uint8 assetType);

    /* //////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @dev Only Pricing Modules can call functions with this modifier.
     */
    modifier onlyPricingModule() {
        require(isPricingModule[msg.sender], "MR: Only PriceMod.");
        _;
    }

    /**
     * @dev Only Accounts can call functions with this modifier.
     * @dev Cannot be called via delegate calls.
     */
    modifier onlyAccount() {
        require(IFactory(factory).isAccount(msg.sender), "MR: Only Accounts.");
        require(address(this) == _this, "MR: No delegate.");
        _;
    }

    /* //////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param factory_ The contract address of the Factory.
     * @dev The mainRegistry must be initialised with baseCurrency USD, at baseCurrencyCounter of 0.
     * Usd is initialised with the following BaseCurrencyInformation.
     * - baseCurrencyToUsdOracleUnit: Since there is no price oracle for usd to USD, this is 1 by default for USD.
     * - baseCurrencyUnitCorrection: We use 18 decimals precision for USD, so unitCorrection is 1 for USD.
     * - assetAddress: Since there is no native token for usd, this is the 0 address by default for USD.
     * - baseCurrencyToUsdOracle: Since there is no price oracle for usd to USD, this is the 0 address by default for USD.
     * - baseCurrencyLabel: 'USD' (only used for readability purpose).
     */
    constructor(address factory_) {
        _this = address(this);
        factory = factory_;

        // Main Registry must be initialised with usd, other values of baseCurrencyToInformation[0] are 0 or the zero-address.
        baseCurrencyToInformation[0].baseCurrencyLabel = "USD";
        // No need for a unit correction, since USD has hardcoded precision of 18 decimals, identical to the internal precision 18 decimals.
        baseCurrencyToInformation[0].baseCurrencyUnitCorrection = 1;
        // "rateUsdToUsd" is hardcoded to 1, with 0 decimals -> "usdToUsdOracleUnit" is 1.
        baseCurrencyToInformation[0].baseCurrencyToUsdOracleUnit = 1;

        // Usd is the first baseCurrency at index 0 of array baseCurrencies.
        isBaseCurrency[address(0)] = true;
        baseCurrencies.push(address(0));
        baseCurrencyCounter = 1;

        emit BaseCurrencyAdded(address(0), 0, "USD");
    }

    /* ///////////////////////////////////////////////////////////////
                        EXTERNAL CONTRACTS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets an allowed action handler.
     * @param action The address of the action handler.
     * @param allowed Bool to indicate its status.
     * @dev Can only be called by owner.
     */
    function setAllowedAction(address action, bool allowed) external onlyOwner {
        isActionAllowed[action] = allowed;

        emit AllowedActionSet(action, allowed);
    }

    /* ///////////////////////////////////////////////////////////////
                        BASE CURRENCY MANAGEMENT
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Adds a new baseCurrency (a unit of account in which price is denominated, like USD or ETH) to the Main Registry.
     * @param baseCurrencyInformation A Struct with information about the BaseCurrency:
     * - baseCurrencyToUsdOracleUnit: The unit of the oracle, equal to 10^decimalsOracle.
     * - baseCurrencyUnitCorrection: The factor with which the baseCurrency should be multiplied to bring it to 18 decimals.
     * - assetAddress: The contract address of the baseCurrency.
     * - baseCurrencyToUsdOracle: The contract address of the pricing oracle for baseCurrency -> USD.
     * - baseCurrencyLabel: Human readable label.
     * @dev If the BaseCurrency has no native token (USD, EUR...), baseCurrencyDecimals is 0 and assetAddress the null address.
     * Tokens pegged to the native token do not count as native tokens.
     * - USDC is not a native token for USD as BaseCurrency.
     * - WETH is a native token for ETH as BaseCurrency.
     * @dev A baseCurrency cannot be added twice, as that would result in the ability to manipulate prices.
     */
    function addBaseCurrency(BaseCurrencyInformation calldata baseCurrencyInformation) external onlyOwner {
        require(!isBaseCurrency[baseCurrencyInformation.assetAddress], "MR_ABC: BaseCurrency exists");

        baseCurrencyToInformation[baseCurrencyCounter] = baseCurrencyInformation;
        assetToBaseCurrency[baseCurrencyInformation.assetAddress] = baseCurrencyCounter;
        isBaseCurrency[baseCurrencyInformation.assetAddress] = true;
        baseCurrencies.push(baseCurrencyInformation.assetAddress);

        unchecked {
            ++baseCurrencyCounter;
        }

        emit BaseCurrencyAdded(
            baseCurrencyInformation.assetAddress, uint8(baseCurrencyCounter), baseCurrencyInformation.baseCurrencyLabel
        );
    }

    /**
     * @notice Sets a new oracle for the rate baseCurrency-USD.
     * @param baseCurrency The identifier of the baseCurrency for which the new oracle is set.
     * @param newOracle The new oracle address.
     * @param baseCurrencyToUsdOracleUnit The new baseCurrencyToUsdOracleUnit.
     * @dev This function is part of an oracle failsafe mechanism.
     * New oracles can only be set if the current oracle is not performing as intended:
     * - A call to the oracle reverts.
     * - The oracle returns the minimum value.
     * - The oracle returns the maximum value.
     * - The oracle didn't update for over a week.
     * @dev This function could be called to set a new oracle address for the baseCurrency USD (since it is initiated with the zero address).
     * This oracle is however never used, hence would not cause any problems (except gas waste).
     */
    function setOracle(uint256 baseCurrency, address newOracle, uint64 baseCurrencyToUsdOracleUnit)
        external
        onlyOwner
    {
        require(baseCurrency < baseCurrencyCounter, "MR_SO: UNKNOWN_BASECURRENCY");

        bool oracleIsHealthy = true;
        address oldOracle = baseCurrencyToInformation[baseCurrency].baseCurrencyToUsdOracle;

        try IChainLinkData(oldOracle).latestRoundData() returns (
            uint80, int256 answer, uint256, uint256 updatedAt, uint80
        ) {
            if (answer <= IChainLinkData(IChainLinkData(oldOracle).aggregator()).minAnswer()) {
                oracleIsHealthy = false;
            } else if (answer >= IChainLinkData(IChainLinkData(oldOracle).aggregator()).maxAnswer()) {
                oracleIsHealthy = false;
            } else if (updatedAt <= block.timestamp - 1 weeks) {
                oracleIsHealthy = false;
            }
        } catch {
            oracleIsHealthy = false;
        }

        if (oracleIsHealthy) {
            revert("MR_SO: ORACLE_HEALTHY");
        } else {
            baseCurrencyToInformation[baseCurrency].baseCurrencyToUsdOracle = newOracle;
            baseCurrencyToInformation[baseCurrency].baseCurrencyToUsdOracleUnit = baseCurrencyToUsdOracleUnit;
        }
    }

    /* ///////////////////////////////////////////////////////////////
                        PRICE MODULE MANAGEMENT
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Adds a new Pricing Module to the Main Registry.
     * @param pricingModule The contract address of the Pricing Module.
     */
    function addPricingModule(address pricingModule) external onlyOwner {
        require(!isPricingModule[pricingModule], "MR_APM: PriceMod. not unique");
        isPricingModule[pricingModule] = true;
        pricingModules.push(pricingModule);

        emit PricingModuleAdded(pricingModule);
    }

    // Todo :natspec + test if we keep it. Used in UNIV2 pricing midules
    function getPricingModuleOfAsset(address asset) public view returns (address pricingModule) {
        pricingModule = assetToAssetInformation[asset].pricingModule;
    }

    /* ///////////////////////////////////////////////////////////////
                        ASSET MANAGEMENT
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Adds a new asset to the Main Registry.
     * @param assetAddress The contract address of the asset.
     * @param assetType Identifier for the type of the asset:
     * 0 = ERC20.
     * 1 = ERC721.
     * 2 = ERC1155.
     * @dev Assets that are already in the mainRegistry cannot be overwritten,
     * as that would make it possible for devs to change the asset pricing.
     */
    function addAsset(address assetAddress, uint256 assetType) external onlyPricingModule {
        require(!inMainRegistry[assetAddress], "MR_AA: Asset already in mainreg");
        require(assetType <= type(uint96).max, "MR_AA: Invalid AssetType");

        inMainRegistry[assetAddress] = true;
        assetsInMainRegistry.push(assetAddress);
        assetToAssetInformation[assetAddress] =
            AssetInformation({ assetType: uint96(assetType), pricingModule: msg.sender });

        emit AssetAdded(assetAddress, msg.sender, uint8(assetType));
    }

    /**
     * @notice Batch deposit multiple assets.
     * @param assetAddresses Array of the contract addresses of the assets.
     * @param assetIds Array of the IDs of the assets.
     * @param amounts Array with the amounts of the assets.
     * @return assetTypes Array with the types of the assets.
     * 0 = ERC20.
     * 1 = ERC721.
     * 2 = ERC1155.
     * @dev increaseExposure in the pricing module checks whether it's allowlisted and updates the exposure.
     */
    function batchProcessDeposit(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata amounts
    ) external whenDepositNotPaused onlyAccount returns (uint256[] memory assetTypes) {
        uint256 addressesLength = assetAddresses.length;
        require(addressesLength == assetIds.length && addressesLength == amounts.length, "MR_BPD: LENGTH_MISMATCH");

        address assetAddress;
        assetTypes = new uint256[](addressesLength);
        for (uint256 i; i < addressesLength;) {
            assetAddress = assetAddresses[i];
            assetTypes[i] = assetToAssetInformation[assetAddress].assetType;

            IPricingModule_New(assetToAssetInformation[assetAddress].pricingModule).processDirectDeposit(
                assetAddress, assetIds[i], amounts[i]
            );

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Batch withdraw multiple assets.
     * @param assetAddresses Array of the contract addresses of the assets.
     * @param assetIds Array of the IDs of the assets.
     * @param amounts Array with the amounts of the assets.
     * @return assetTypes Array with the types of the assets.
     * 0 = ERC20.
     * 1 = ERC721.
     * 2 = ERC1155.
     * @dev batchProcessWithdrawal in the pricing module updates the exposure.
     */
    function batchProcessWithdrawal(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata amounts
    ) external whenWithdrawNotPaused onlyAccount returns (uint256[] memory assetTypes) {
        uint256 addressesLength = assetAddresses.length;
        require(addressesLength == assetIds.length && addressesLength == amounts.length, "MR_BPW: LENGTH_MISMATCH");

        address assetAddress;
        assetTypes = new uint256[](addressesLength);
        for (uint256 i; i < addressesLength;) {
            assetAddress = assetAddresses[i];
            assetTypes[i] = assetToAssetInformation[assetAddress].assetType;

            IPricingModule_New(assetToAssetInformation[assetAddress].pricingModule).processDirectWithdrawal(
                assetAddress, assetIds[i], amounts[i]
            );

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This function is called by pricing modules of non-primary assets in order to increase the exposure of the underlying asset.
     * @param underlyingAsset The underlying asset of a non-primary asset.
     * @param underlyingAssetId The underlying asset ID.
     * @param exposureAssetToUnderlyingAsset The amount of exposure of the upper asset (asset in previous pricing module called) to the underlying asset.
     * @param deltaExposureAssetToUnderlyingAsset The increase or decrease in exposure of the upper asset to the underlying asset since last update.
     */
    function getUsdValueExposureToUnderlyingAssetAfterDeposit(
        address underlyingAsset,
        uint256 underlyingAssetId,
        uint256 exposureAssetToUnderlyingAsset,
        int256 deltaExposureAssetToUnderlyingAsset
    ) external onlyPricingModule returns (uint256 usdValueExposureAssetToUnderlyingAsset) {
        (, usdValueExposureAssetToUnderlyingAsset) = IPricingModule_New(
            assetToAssetInformation[underlyingAsset].pricingModule
        ).processIndirectDeposit(
            underlyingAsset, underlyingAssetId, exposureAssetToUnderlyingAsset, deltaExposureAssetToUnderlyingAsset
        );
    }

    /**
     * @notice This function is called by pricing modules of non-primary assets in order to decrease the exposure of the underlying asset.
     * @param underlyingAsset The underlying asset of a non-primary asset.
     * @param underlyingAssetId The underlying asset ID.
     * @param exposureAssetToUnderlyingAsset The amount of exposure of the upper asset (asset in previous pricing module called) to the underlying asset.
     * @param deltaExposureAssetToUnderlyingAsset The increase or decrease in exposure of the upper asset to the underlying asset since last update.
     */
    function getUsdValueExposureToUnderlyingAssetAfterWithdrawal(
        address underlyingAsset,
        uint256 underlyingAssetId,
        uint256 exposureAssetToUnderlyingAsset,
        int256 deltaExposureAssetToUnderlyingAsset
    ) external onlyPricingModule returns (uint256 usdValueExposureAssetToUnderlyingAsset) {
        (, usdValueExposureAssetToUnderlyingAsset) = IPricingModule_New(
            assetToAssetInformation[underlyingAsset].pricingModule
        ).processIndirectWithdrawal(
            underlyingAsset, underlyingAssetId, exposureAssetToUnderlyingAsset, deltaExposureAssetToUnderlyingAsset
        );
    }

    /* ///////////////////////////////////////////////////////////////
                          PRICING LOGIC
    /////////////////////////////////////////////////////////////// */

    function getUsdValue(IPricingModule_New.GetValueInput memory getValueInput)
        external
        view
        returns (uint256 usdValue)
    {
        // Fetch the Value and the risk variables in the PricingModule.
        (usdValue,,) =
            IPricingModule_New(assetToAssetInformation[getValueInput.asset].pricingModule).getValue(getValueInput);
    }

    /**
     * @notice Calculates the value per asset, denominated in a given BaseCurrency.
     * @param assetAddresses Array of the contract addresses of the assets.
     * @param assetIds Array of the IDs of the assets.
     * @param assetAmounts Array with the amounts of the assets.
     * @param baseCurrency An identifier (uint256) of the BaseCurrency.
     * @return valuesAndRiskVarPerAsset The array of values per assets, denominated in BaseCurrency.
     * @dev For each token address, a corresponding id and amount at the same index should be present,
     * for tokens without Id (ERC20 for instance), the Id should be set to 0.
     * @dev No checks of input parameters necessary, all generated by the Account.
     * Additionally, unknown assetAddresses cause IPricingModule(assetAddresses) to revert,
     * Unknown baseCurrency will cause IChainLinkData(baseCurrency) to revert.
     * Non-equal lists will or revert, or not take all assets into account -> lower value as actual.
     */
    function getListOfValuesPerAsset(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata assetAmounts,
        uint256 baseCurrency
    ) public view returns (RiskModule.AssetValueAndRiskVariables[] memory) {
        // Cache Output array.
        uint256 assetAddressesLength = assetAddresses.length;
        RiskModule.AssetValueAndRiskVariables[] memory valuesAndRiskVarPerAsset =
            new RiskModule.AssetValueAndRiskVariables[](assetAddressesLength);

        // Cache variables.
        IPricingModule_New.GetValueInput memory getValueInput;
        getValueInput.baseCurrency = baseCurrency;
        BaseCurrencyInformation memory baseCurrencyInformation = baseCurrencyToInformation[baseCurrency];
        int256 rateBaseCurrencyToUsd;
        address assetAddress;
        uint256 valueInUsd;

        if (baseCurrency > 0) {
            // Get the baseCurrency-USD rate if the BaseCurrency is different from USD (identifier 0).
            (, rateBaseCurrencyToUsd,,,) =
                IChainLinkData(baseCurrencyInformation.baseCurrencyToUsdOracle).latestRoundData();
        } else {
            // If baseCurrency is USD, set "rateUsdToUsd" to 1.
            // Both USD and the internal precision of calculations have 18 decimals.
            rateBaseCurrencyToUsd = 1;
        }

        // Loop over all assets.
        for (uint256 i; i < assetAddressesLength;) {
            assetAddress = assetAddresses[i];

            // If the asset is identical to the base Currency, we do not need to get a rate.
            // We only need to fetch the risk variables from the PricingModule.
            if (assetAddress == baseCurrencyInformation.assetAddress) {
                valuesAndRiskVarPerAsset[i].valueInBaseCurrency = assetAmounts[i];
                (valuesAndRiskVarPerAsset[i].collateralFactor, valuesAndRiskVarPerAsset[i].liquidationFactor) =
                IPricingModule_New(assetToAssetInformation[assetAddress].pricingModule).getRiskVariables(
                    assetAddress, baseCurrency
                );

                // Else we need to fetch the value in the assets' PricingModule.
            } else {
                // Prepare input.
                getValueInput.asset = assetAddress;
                getValueInput.assetId = assetIds[i];
                getValueInput.assetAmount = assetAmounts[i];

                // Fetch the Value and the risk variables in the PricingModule.
                (
                    valueInUsd,
                    valuesAndRiskVarPerAsset[i].collateralFactor,
                    valuesAndRiskVarPerAsset[i].liquidationFactor
                ) = IPricingModule_New(assetToAssetInformation[assetAddress].pricingModule).getValue(getValueInput);

                // Calculate "valueInBaseCurrency" from "valueInUsd" by dividing by the "rateBaseCurrencyToUsd".
                // Bring the "valueInBaseCurrency" from internal 18 decimals to the actual number of decimals of "baseCurrency".
                unchecked {
                    valuesAndRiskVarPerAsset[i].valueInBaseCurrency = (
                        valueInUsd.mulDivDown(
                            baseCurrencyInformation.baseCurrencyToUsdOracleUnit, uint256(rateBaseCurrencyToUsd)
                        )
                    ) / baseCurrencyInformation.baseCurrencyUnitCorrection;
                }
            }
            unchecked {
                ++i;
            }
        }
        return valuesAndRiskVarPerAsset;
    }

    /**
     * @notice Calculates the values per asset, denominated in a given BaseCurrency.
     * @param assetAddresses Array of the contract addresses of the assets.
     * @param assetIds Array of the IDs of the assets.
     * @param assetAmounts Array with the amounts of the assets.
     * @param baseCurrency The contract address of the BaseCurrency.
     * @return valuesAndRiskVarPerAsset The array of values per assets, denominated in BaseCurrency.
     * @dev No need to check equality of length of arrays, since they are generated by the Account.
     */
    function getListOfValuesPerAsset(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata assetAmounts,
        address baseCurrency
    ) external view returns (RiskModule.AssetValueAndRiskVariables[] memory valuesAndRiskVarPerAsset) {
        require(isBaseCurrency[baseCurrency], "MR_GLVA: UNKNOWN_BASECURRENCY");
        valuesAndRiskVarPerAsset =
            getListOfValuesPerAsset(assetAddresses, assetIds, assetAmounts, assetToBaseCurrency[baseCurrency]);
    }

    /**
     * @notice Calculates the combined value of a combination of assets, denominated in a given BaseCurrency.
     * @param assetAddresses Array of the contract addresses of the assets.
     * @param assetIds Array of the IDs of the assets.
     * @param assetAmounts Array with the amounts of the assets.
     * @param baseCurrency The contract address of the BaseCurrency.
     * @return valueInBaseCurrency The combined value of the assets, denominated in BaseCurrency.
     * @dev No need to check equality of length of arrays, since they are generated by the Account.
     */
    function getTotalValue(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata assetAmounts,
        address baseCurrency
    ) public view returns (uint256 valueInBaseCurrency) {
        require(isBaseCurrency[baseCurrency], "MR_GTV: UNKNOWN_BASECURRENCY");

        RiskModule.AssetValueAndRiskVariables[] memory valuesAndRiskVarPerAsset =
            getListOfValuesPerAsset(assetAddresses, assetIds, assetAmounts, assetToBaseCurrency[baseCurrency]);

        for (uint256 i = 0; i < valuesAndRiskVarPerAsset.length;) {
            valueInBaseCurrency += valuesAndRiskVarPerAsset[i].valueInBaseCurrency;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Calculates the collateralValue of a combination of assets, denominated in a given BaseCurrency.
     * @param assetAddresses Array of the contract addresses of the assets.
     * @param assetIds Array of the IDs of the assets.
     * @param assetAmounts Array with the amounts of the assets.
     * @param baseCurrency The contract address of the BaseCurrency.
     * @return collateralValue The collateral value of the assets, denominated in BaseCurrency.
     * @dev No need to check equality of length of arrays, since they are generated by the Account.
     * @dev The collateral value is equal to the spot value of the assets,
     * discounted by a haircut (the collateral factor).
     */
    function getCollateralValue(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata assetAmounts,
        address baseCurrency
    ) external view returns (uint256 collateralValue) {
        require(isBaseCurrency[baseCurrency], "MR_GCV: UNKNOWN_BASECURRENCY");

        RiskModule.AssetValueAndRiskVariables[] memory valuesAndRiskVarPerAsset =
            getListOfValuesPerAsset(assetAddresses, assetIds, assetAmounts, assetToBaseCurrency[baseCurrency]);

        collateralValue = RiskModule.calculateCollateralValue(valuesAndRiskVarPerAsset);
    }

    /**
     * @notice Calculates the getLiquidationValue of a combination of assets, denominated in a given BaseCurrency.
     * @param assetAddresses Array of the contract addresses of the assets.
     * @param assetIds Array of the IDs of the assets.
     * @param assetAmounts Array with the amounts of the assets.
     * @param baseCurrency The contract address of the BaseCurrency.
     * @return liquidationValue The liquidation value of the assets, denominated in BaseCurrency.
     * @dev No need to check equality of length of arrays, since they are generated by the Account.
     * @dev The liquidation value is equal to the spot value of the assets,
     * discounted by a haircut (the liquidation factor).
     */
    function getLiquidationValue(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata assetAmounts,
        address baseCurrency
    ) external view returns (uint256 liquidationValue) {
        require(isBaseCurrency[baseCurrency], "MR_GLV: UNKNOWN_BASECURRENCY");

        RiskModule.AssetValueAndRiskVariables[] memory valuesAndRiskVarPerAsset =
            getListOfValuesPerAsset(assetAddresses, assetIds, assetAmounts, assetToBaseCurrency[baseCurrency]);

        liquidationValue = RiskModule.calculateLiquidationValue(valuesAndRiskVarPerAsset);
    }
}
