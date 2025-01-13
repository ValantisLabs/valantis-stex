// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ISovereignALM} from "lib/valantis-core/src/ALM/interfaces/ISovereignALM.sol";
import {ALMLiquidityQuoteInput, ALMLiquidityQuote} from "lib/valantis-core/src/ALM/structs/SovereignALMStructs.sol";
import {ISovereignPool} from "lib/valantis-core/src/pools/interfaces/ISovereignPool.sol";

import {Fee} from "./Fee.sol";
import {IStakingProtocol} from "./interfaces/IStakingProtocol.sol";

contract HAMM is ISovereignALM, Fee {
    error HAMM__ZeroAddress();
    error HAMM_getLiquidityQuote_invalidSwapDirection();

    IStakingProtocol public immutable stakingProtocol;

    constructor(address _pool, address _stakingProtocol) Fee(_pool) {
        if (_stakingProtocol == address(0)) revert HAMM__ZeroAddress();

        stakingProtocol = IStakingProtocol(_stakingProtocol);
    }

    /**
     * @notice Called by the Sovereign pool to request a liquidity quote from the ALM.
     * @param _almLiquidityQuoteInput Contains fundamental data about the swap.
     * @return quote quote containing tokenIn and tokenOut amounts filled.
     */
    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _almLiquidityQuoteInput,
        bytes calldata /*_externalContext*/,
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
    function onDepositLiquidityCallback(
        uint256 _amount0,
        uint256 _amount1,
        bytes memory _data
    ) external override {}

    /**
     * @notice Callback to ALM after swap into liquidity pool.
     * @dev Only callable by pool.
     * @param _amountIn Amount of tokenIn in swap.
     */
    function onSwapCallback(
        bool /*_isZeroToOne*/,
        uint256 _amountIn,
        uint256 /*_amountOut*/
    ) external override onlyPool {
        // Withdraw token0 amount received from pool into this contract
        ISovereignPool(pool).withdrawLiquidity(
            _amountIn,
            0,
            address(0),
            address(this),
            new bytes(0)
        );

        // Send token0 amount to staking protocol's withdrawal queue
        // TODO: mark recipient as the LP withdrawal module
        stakingProtocol.burn(address(this), _amountIn);
    }
}
