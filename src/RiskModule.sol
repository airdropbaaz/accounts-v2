/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

/**
 * @title Risk Module
 * @author Pragma Labs
 * @notice The Risk Module is responsible for calculating the risk weighted values of combinations of assets.
 */
library RiskModule {
    /*///////////////////////////////////////////////////////////////
                        CONSTANTS
    ///////////////////////////////////////////////////////////////*/

    uint256 internal constant ONE_4 = 10_000;

    // Struct with risk and valuation related information for a certain asset.
    struct AssetValueAndRiskFactors {
        // The value of the asset.
        uint256 assetValue;
        // The collateral factor of the asset, for a given creditor.
        uint256 collateralFactor;
        // The liquidation factor of the asset, for a given creditor.
        uint256 liquidationFactor;
    }

    /*///////////////////////////////////////////////////////////////
                        RISK FACTORS
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates the collateral value given a combination of asset values and corresponding collateral factors.
     * @param valuesAndRiskFactors Array of asset values and corresponding collateral factors.
     * @return collateralValue The collateral value of the given assets.
     */
    function _calculateCollateralValue(AssetValueAndRiskFactors[] memory valuesAndRiskFactors)
        internal
        pure
        returns (uint256 collateralValue)
    {
        for (uint256 i; i < valuesAndRiskFactors.length;) {
            collateralValue += valuesAndRiskFactors[i].assetValue * valuesAndRiskFactors[i].collateralFactor;
            unchecked {
                ++i;
            }
        }
        collateralValue = collateralValue / ONE_4;
    }

    /**
     * @notice Calculates the liquidation value given a combination of asset values and corresponding liquidation factors.
     * @param valuesAndRiskFactors List of asset values and corresponding liquidation factors.
     * @return liquidationValue The liquidation value of the given assets.
     */
    function _calculateLiquidationValue(AssetValueAndRiskFactors[] memory valuesAndRiskFactors)
        internal
        pure
        returns (uint256 liquidationValue)
    {
        for (uint256 i; i < valuesAndRiskFactors.length;) {
            liquidationValue += valuesAndRiskFactors[i].assetValue * valuesAndRiskFactors[i].liquidationFactor;
            unchecked {
                ++i;
            }
        }
        liquidationValue = liquidationValue / ONE_4;
    }
}
