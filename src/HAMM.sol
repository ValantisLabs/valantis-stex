// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ALMLiquidityQuoteInput, ALMLiquidityQuote} from "@valantis-core/ALM/structs/SovereignALMStructs.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {SwapFee} from "./SwapFee.sol";
import {IWithdrawalModule} from "./interfaces/IWithdrawalModule.sol";
import {IHAMM} from "./interfaces/IHAMM.sol";

contract HAMM is IHAMM, SwapFee, ERC20, ReentrancyGuardTransient {
    using SafeERC20 for ERC20;

    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error HAMM__OnlyWithdrawalModule();
    error HAMM__ZeroAddress();
    error HAMM__deposit_lessThanMinShares();
    error HAMM__deposit_zeroShares();
    error HAMM__setManagerFeeBips_invalidManagerFeeBips();
    error HAMM__withdraw_insufficientToken0Withdrawn();
    error HAMM__withdraw_insufficientToken1Withdrawn();
    error HAMM__withdraw_zeroShares();
    error HAMM___checkDeadline_expired();

    /**
     *
     *  CONSTANTS
     *
     */
    uint256 private constant MINIMUM_LIQUIDITY = 1e9;

    /**
     *
     *  IMMUTABLES
     *
     */
    IWithdrawalModule public immutable withdrawalModule;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _pool, address _owner, address _withdrawalModule)
        SwapFee(_pool, _owner)
        ERC20("Hyped AMM LP", "HAMM")
    {
        if (_pool == address(0) || _owner == address(0) || _withdrawalModule == address(0)) revert HAMM__ZeroAddress();

        withdrawalModule = IWithdrawalModule(_withdrawalModule);
    }

    /**
     *
     *  MODIFIERS
     *
     */
    modifier onlyWithdrawalModule() {
        if (msg.sender != address(withdrawalModule)) {
            revert HAMM__OnlyWithdrawalModule();
        }
        _;
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */
    function unstakeToken0Reserves() external override onlyWithdrawalModule nonReentrant {
        (uint256 reserve0,) = _pool.getReserves();
        _pool.withdrawLiquidity(reserve0, 0, msg.sender, msg.sender, new bytes(0));
    }

    function replenishPool(uint256 _amount) external override onlyWithdrawalModule nonReentrant {
        _pool.depositLiquidity(0, _amount, msg.sender, new bytes(0), abi.encode(msg.sender));
    }

    /**
     * @notice Deposit liquidity into `pool` and mint LP tokens.
     * @param _amount Amount of token1 deposited.
     * @param _minShares Minimum amount of shares to mint.
     * @param _deadline Block timestamp after which this call reverts.
     * @param _recipient Address to mint LP tokens for.
     * @return shares Amount of shares minted.
     */
    function deposit(uint256 _amount, uint256 _minShares, uint256 _deadline, address _recipient)
        external
        override
        nonReentrant
        returns (uint256 shares)
    {
        _checkDeadline(_deadline);

        uint256 totalSupplyCache = totalSupply();
        if (totalSupplyCache == 0) {
            _mint(address(1), MINIMUM_LIQUIDITY);

            shares = _amount - MINIMUM_LIQUIDITY;
        } else {
            (, uint256 reserve1) = _pool.getReserves();

            shares = Math.mulDiv(_amount, totalSupplyCache, reserve1 + withdrawalModule.amountPendingUnstaking());
        }

        if (shares < _minShares) revert HAMM__deposit_lessThanMinShares();

        if (shares == 0) revert HAMM__deposit_zeroShares();

        _mint(_recipient, shares);

        _pool.depositLiquidity(0, _amount, msg.sender, new bytes(0), abi.encode(msg.sender));
    }

    /**
     * @notice Callback to transfer tokens from user into `pool` during deposits.
     */
    function onDepositLiquidityCallback(
        uint256,
        /*_amount0*/
        uint256 _amount1,
        bytes memory _data
    ) external override onlyPool {
        address user = abi.decode(_data, (address));

        // Only token1 deposits are allowed
        if (_amount1 > 0) {
            ERC20(_pool.token1()).safeTransferFrom(user, msg.sender, _amount1);
        }
    }

    /**
     * @notice Withdraw liquidity from `pool` and burn LP tokens.
     * @param _shares Amount of LP tokens to burn.
     * @param _amount0Min Minimum amount of token0 required for `_recipient`.
     * @param _amount1Min Minimum amount of token1 required for `_recipient`.
     * @param _deadline Block timestamp after which this call reverts.
     * @param _recipient Address to receive token0 and token1 amounts.
     * @return amount0 Amount of token0 withdrawn. WARNING: Potentially innacurate in case token0 is rebase.
     * @return amount1 Amount of token1 withdrawn. WARNING: Potentially innacurate in case token1 is rebase.
     */
    function withdraw(uint256 _shares, uint256 _amount0Min, uint256 _amount1Min, uint256 _deadline, address _recipient)
        external
        override
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        _checkDeadline(_deadline);

        if (_shares == 0) revert HAMM__withdraw_zeroShares();

        if (_recipient == address(0)) {
            revert HAMM__ZeroAddress();
        }

        (, uint256 reserve1) = _pool.getReserves();

        uint256 totalSupplyCache = totalSupply();
        // token0 amount calculated as pro-rata share of token0 pending in withdrawal queue
        amount0 = Math.mulDiv(withdrawalModule.amountPendingUnstaking(), _shares, totalSupplyCache);
        // token1 amount calculated as pro-rata share of token1 reserves in the pool
        amount1 = Math.mulDiv(reserve1, _shares, totalSupplyCache);

        // Slippage protection checks
        if (amount0 < _amount0Min) {
            revert HAMM__withdraw_insufficientToken0Withdrawn();
        }
        if (amount1 < _amount1Min) {
            revert HAMM__withdraw_insufficientToken1Withdrawn();
        }

        // Burn LP tokens
        _burn(msg.sender, _shares);

        // Send token0 withdrawal request to withdrawal module,
        // to be processed asynchronously
        if (amount0 > 0) {
            withdrawalModule.burnAfterWithdraw(amount0, _recipient);
        }

        // Withdraw token1 amount from pool and send to recipient
        if (amount1 > 0) {
            _pool.withdrawLiquidity(0, amount1, msg.sender, _recipient, new bytes(0));
        }
    }

    /**
     * @notice Called by the Sovereign pool to request a liquidity quote from this Liquidity Module.
     * @param _almLiquidityQuoteInput Contains fundamental data about the swap.
     * @return quote Struct containing tokenIn and tokenOut amounts filled.
     */
    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _almLiquidityQuoteInput,
        bytes calldata, /*_externalContext*/
        bytes calldata /*_verifierData*/
    ) external pure override returns (ALMLiquidityQuote memory quote) {
        quote.amountInFilled = _almLiquidityQuoteInput.amountInMinusFee;
        quote.amountOut = quote.amountInFilled;
    }

    /**
     * @notice Callback to Liquidity Module after swap into liquidity pool.
     * @dev Not implemented.
     */
    function onSwapCallback(
        bool,
        /*_isZeroToOne*/
        uint256, /*_amountIn*/
        uint256 /*_amountOut*/
    ) external override {}

    /**
     *
     *  PRIVATE FUNCTIONS
     *
     */
    function _checkDeadline(uint256 deadline) private view {
        if (block.timestamp > deadline) revert HAMM___checkDeadline_expired();
    }
}
