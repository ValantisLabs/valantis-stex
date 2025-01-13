// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ISovereignALM} from "lib/valantis-core/src/ALM/interfaces/ISovereignALM.sol";
import {ALMLiquidityQuoteInput, ALMLiquidityQuote} from "lib/valantis-core/src/ALM/structs/SovereignALMStructs.sol";

import {Fee} from "./Fee.sol";

contract HAMM is ISovereignALM, Fee {
    error HAMM_getLiquidityQuote_invalidSwapDirection();

    constructor(address _pool) Fee(_pool) {}

    /**
     * @notice Called by the Sovereign pool to request a liquidity quote from the ALM.
     * @param _almLiquidityQuoteInput Contains fundamental data about the swap.
     * @return quote quote containing tokenIn and tokenOut amounts filled.
     */
    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _almLiquidityQuoteInput,
        bytes calldata, /*_externalContext*/
        bytes calldata /*_verifierData*/
    ) external view override returns (ALMLiquidityQuote memory quote) {
        // Only swaps where tokenIn=token0 and tokenOut=token1 are allowed
        if (!_almLiquidityQuoteInput.isZeroToOne) {
            revert HAMM_getLiquidityQuote_invalidSwapDirection();
        }

        uint256 feePips = getFee();

        quote.isCallbackOnSwap = true;
        quote.amountInFilled = _almLiquidityQuoteInput.amountInMinusFee;
        quote.amountOut = (quote.amountInFilled * (PIPS - feePips)) / PIPS;
    }

    /**
     * @notice Callback function for `depositLiquidity` .
     * @param _amount0 Amount of token0 being deposited.
     * @param _amount1 Amount of token1 being deposited.
     * @param _data Context data passed by the ALM, while calling `depositLiquidity`.
     */
    function onDepositLiquidityCallback(uint256 _amount0, uint256 _amount1, bytes memory _data) external override {}

    /**
     * @notice Callback to ALM after swap into liquidity pool.
     * @dev Only callable by pool.
     * @param _isZeroToOne Direction of swap.
     * @param _amountIn Amount of tokenIn in swap.
     * @param _amountOut Amount of tokenOut in swap.
     */
    function onSwapCallback(bool _isZeroToOne, uint256 _amountIn, uint256 _amountOut) external override {
        // TODO: unstake logic
    }
}
