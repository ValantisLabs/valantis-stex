// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SwapFeeModuleData} from "@valantis-core/swap-fee-modules/interfaces/ISwapFeeModule.sol";

/**
 * @notice A version of valantis-core `ISwapFeeModuleMinimal` where `getSwapFeeInBips` is read-only.
 */
interface ISwapFeeModuleMinimalView {
    /**
     * @notice Returns the swap fee in bips for both Universal & Sovereign Pools.
     *     @param _tokenIn The address of the token that the user wants to swap.
     *     @param _tokenOut The address of the token that the user wants to receive.
     *     @param _amountIn The amount of tokenIn being swapped.
     *     @param _user The address of the user.
     *     @param _swapFeeModuleContext Arbitrary bytes data which can be sent to the swap fee module.
     *     @return swapFeeModuleData A struct containing the swap fee in bips, and internal context data.
     */
    function getSwapFeeInBips(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        address _user,
        bytes memory _swapFeeModuleContext
    ) external view returns (SwapFeeModuleData memory swapFeeModuleData);
}
