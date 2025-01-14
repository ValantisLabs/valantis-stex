// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ISovereignALM} from "@valantis-core/ALM/interfaces/ISovereignALM.sol";
import {ALMLiquidityQuoteInput, ALMLiquidityQuote} from "@valantis-core/ALM/structs/SovereignALMStructs.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";

import {Fee} from "./Fee.sol";
import {IWithdrawalModule} from "./interfaces/IWithdrawalModule.sol";

contract HAMM is ISovereignALM, Fee {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error HAMM__ZeroAddress();
    error HAMM_getLiquidityQuote_invalidSwapDirection();
    error HAMM___checkDeadline_expired();

    /**
     *
     *  IMMUTABLES
     *
     */
    IWithdrawalModule public immutable withdrawalModule;

    /**
     *
     *  STORAGE
     *
     */
    uint256 public amountToken0Queue;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _pool, address _withdrawalModule) Fee(_pool) {
        if (_withdrawalModule == address(0)) revert HAMM__ZeroAddress();

        withdrawalModule = IWithdrawalModule(_withdrawalModule);
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Deposit liquidity into `pool` and mint LP tokens.
     * @param _amount Amount of token1 deposited.
     * @param _minShares Minimum amount of shares to mint.
     * @param _deadline Block timestamp after which this call reverts.
     * @param _recipient Address to mint LP tokens for.
     * @return shares Amount of shares minted.
     */
    function deposit(
        uint256 _amount,
        uint256 _minShares,
        uint256 _deadline,
        address _recipient
    ) external returns (uint256 shares, uint256 amount) {
        _checkDeadline(_deadline);

        /*uint256 totalSupplyCache = totalSupply();
        if (totalSupplyCache == 0) {
            _mint(address(1), MINIMUM_LIQUIDITY);

            shares = _amount - MINIMUM_LIQUIDITY;
        } else {
            (, uint256 reserve1) = pool.getReserves();

            shares = Math.mulDiv(
                _amount,
                totalSupplyCache,
                reserve1 + amountToken0Queue
            );
        }

        if (shares < _minShares) revert HAMM__deposit_lessThanMinShares();

        if (shares == 0) revert HAMM__deposit_zeroShares();

        _mint(_recipient, shares);

        (, amount) = pool.depositLiquidity(
            0,
            _amount,
            msg.sender,
            new bytes(0),
            abi.encode(msg.sender)
        );*/
    }

    /**
     * @notice Called by the Sovereign pool to request a liquidity quote from this Liquidity Module.
     * @param _almLiquidityQuoteInput Contains fundamental data about the swap.
     * @return quote Struct containing tokenIn and tokenOut amounts filled.
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
     * @notice Callback function for `depositLiquidity`.
     * @param _amount0 Amount of token0 being deposited.
     * @param _amount1 Amount of token1 being deposited.
     * @param _data Context data passed by the Liquidity Module, while calling `depositLiquidity`.
     */
    function onDepositLiquidityCallback(
        uint256 _amount0,
        uint256 _amount1,
        bytes memory _data
    ) external override onlyPool {}

    /**
     * @notice Callback to Liquidity Module after swap into liquidity pool.
     * @dev Only callable by pool.
     * @param _amountIn Amount of tokenIn in swap.
     */
    function onSwapCallback(
        bool,
        /*_isZeroToOne*/ uint256 _amountIn,
        uint256 /*_amountOut*/
    ) external override onlyPool {
        // Transfer token0 amount received from pool into withdrawal module
        ISovereignPool(pool).withdrawLiquidity(
            _amountIn,
            0,
            address(0),
            address(withdrawalModule),
            new bytes(0)
        );

        // Send token0 amount to staking protocol's withdrawal queue
        withdrawalModule.burn(_amountIn);

        amountToken0Queue += _amountIn;
    }

    function _checkDeadline(uint256 deadline) private view {
        if (block.timestamp > deadline) revert HAMM___checkDeadline_expired();
    }
}
