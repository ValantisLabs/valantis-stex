// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ALMLiquidityQuoteInput, ALMLiquidityQuote} from "@valantis-core/ALM/structs/SovereignALMStructs.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import {IProtocolFactory} from "@valantis-core/protocol-factory/interfaces/IProtocolFactory.sol";
import {SovereignPoolConstructorArgs} from "@valantis-core/pools/structs/SovereignPoolStructs.sol";
import {SwapFeeModuleData} from "@valantis-core/swap-fee-modules/interfaces/ISwapFeeModule.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {IWithdrawalModule} from "./interfaces/IWithdrawalModule.sol";
import {IHAMM} from "./interfaces/IHAMM.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {ISwapFeeModuleMinimalView} from "./interfaces/ISwapFeeModuleMinimalView.sol";

contract HAMM is IHAMM, Ownable, ERC20, ReentrancyGuardTransient {
    using SafeERC20 for ERC20;

    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error HAMM__OnlyPool();
    error HAMM__OnlyWithdrawalModule();
    error HAMM__ZeroAddress();
    error HAMM__deposit_lessThanMinShares();
    error HAMM__deposit_zeroShares();
    error HAMM__onSwapCallback_NotImplemented();
    error HAMM__receive_onlyWETH9();
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
    uint256 private constant BIPS = 10_000;
    uint256 private constant MINIMUM_LIQUIDITY = 1e9;

    /**
     *
     *  IMMUTABLES
     *
     */

    /**
     * @notice Address of Valantis Sovereign Pool.
     */
    address public immutable pool;

    /**
     * @notice Address of Valantis Swap Fee Module.
     */
    address public immutable swapFeeModule;

    /**
     * @notice Address of LST token.
     */
    address public immutable token0;
    /**
     * @notice Address of wrapped native token.
     */
    address public immutable token1;

    /**
     * @notice Address of pool manager fee recipients.
     */
    address public immutable poolFeeRecipient1;
    address public immutable poolFeeRecipient2;

    /**
     * @notice Address of Withdrawal Module.
     */
    address public immutable withdrawalModule;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(
        address _token0,
        address _token1,
        address _swapFeeModule,
        address _protocolFactory,
        address _poolFeeRecipient1,
        address _poolFeeRecipient2,
        address _owner,
        address _withdrawalModule
    ) Ownable(_owner) ERC20("Hyped AMM LP", "HAMM") {
        if (
            _token0 == address(0) || _token1 == address(0) || _swapFeeModule == address(0)
                || _protocolFactory == address(0) || _poolFeeRecipient1 == address(0) || _poolFeeRecipient2 == address(0)
                || _owner == address(0) || _withdrawalModule == address(0)
        ) revert HAMM__ZeroAddress();

        SovereignPoolConstructorArgs memory args = SovereignPoolConstructorArgs(
            _token0,
            _token1,
            _protocolFactory,
            address(this),
            address(0),
            address(0),
            true, // token0 and token1 reserves will be measured as pool's balances
            true, // but token0 and token1 should not be rebase
            0, // Rounding error tolerance on transfers is 0, since token0 and token1 cannot be rebase
            0,
            0
        );

        pool = IProtocolFactory(_protocolFactory).deploySovereignPool(args);

        ISovereignPool(pool).setSwapFeeModule(_swapFeeModule);
        ISovereignPool(pool).setALM(address(this));

        swapFeeModule = _swapFeeModule;

        poolFeeRecipient1 = _poolFeeRecipient1;
        poolFeeRecipient2 = _poolFeeRecipient2;

        token0 = _token0;
        token1 = _token1;

        withdrawalModule = _withdrawalModule;
    }

    /**
     *
     *  MODIFIERS
     *
     */
    modifier onlyPool() {
        if (msg.sender != pool) {
            revert HAMM__OnlyPool();
        }
        _;
    }

    modifier onlyWithdrawalModule() {
        if (msg.sender != withdrawalModule) {
            revert HAMM__OnlyWithdrawalModule();
        }
        _;
    }

    /**
     *
     *  VIEW FUNCTIONS
     *
     */

    /**
     * @notice Helper function to estimate swap quote amounts.
     * @dev WARNING: This function has minimal internal checks,
     *      do not use for accurate simulation for `SovereignPool::swap`.
     * @param _tokenIn Address of input token to swap.
     * @param _amountIn Amount if `_tokenIn` to swap.
     * @return amountOut Amount of output token received.
     */
    function getAmountOut(address _tokenIn, uint256 _amountIn) public view returns (uint256 amountOut) {
        if (_tokenIn != token0 && _tokenIn != token1) return 0;

        SwapFeeModuleData memory swapFeeData = ISwapFeeModuleMinimalView(swapFeeModule).getSwapFeeInBips(
            _tokenIn, address(0), _amountIn, address(0), new bytes(0)
        );

        uint256 amountInWithoutFee = Math.mulDiv(_amountIn, BIPS, BIPS + swapFeeData.feeInBips);
        bool isZeroToOne = _tokenIn == token0;
        IWithdrawalModule withdrawalModuleInterface = IWithdrawalModule(withdrawalModule);
        // token0 balances might not be 1:1 mapped to token1 balances,
        // hence we rely on the withdrawalModule to convert it (e.g., if token0 balances represent shares)
        amountOut = isZeroToOne
            ? withdrawalModuleInterface.convertToToken1(amountInWithoutFee)
            : withdrawalModuleInterface.convertToToken0(amountInWithoutFee);
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */
    receive() external payable {
        if (msg.sender != token1) revert HAMM__receive_onlyWETH9();
    }

    /**
     * @notice Sets a manager/protocol fee on every swap.
     * @dev Only callable by `owner`.
     * @param _poolManagerFeeBips New pool manager fee to apply in `pool`.
     */
    function setPoolManagerFeeBips(uint256 _poolManagerFeeBips) external override onlyOwner nonReentrant {
        ISovereignPool(pool).setPoolManagerFeeBips(_poolManagerFeeBips);
    }

    function claimPoolManagerFees() external override nonReentrant {
        // token0 fees are automatically sent to this contract (poolManager) on every swap,
        // because of SovereignPool::swap behavior for rebase input token
        // No fees are applied on token1 -> token0 swaps
        uint256 fee0Received = ERC20(token0).balanceOf(address(this));

        // 50/50 split between `poolFeeRecipient1` and `poolFeeRecipient2`

        if (fee0Received > 0) {
            uint256 fee0ToRecipient1 = fee0Received / 2;
            if (fee0ToRecipient1 > 0) {
                ERC20(token0).safeTransfer(poolFeeRecipient1, fee0ToRecipient1);
            }

            uint256 fee0ToRecipient2 = fee0Received - fee0ToRecipient1;
            if (fee0ToRecipient2 > 0) {
                ERC20(token0).safeTransfer(poolFeeRecipient2, fee0ToRecipient2);
            }
        }
    }

    /**
     * @notice Allows the withdrawal module to transfer `token0` reserves from `pool`
     *         and send those to the staking protocol's native withdrawal queue.
     * @dev Only callable by `withdrawalModule`.
     */
    function unstakeToken0Reserves() external override onlyWithdrawalModule nonReentrant {
        ISovereignPool poolInterface = ISovereignPool(pool);

        (uint256 reserve0,) = poolInterface.getReserves();
        poolInterface.withdrawLiquidity(reserve0, 0, msg.sender, msg.sender, new bytes(0));
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
            (uint256 reserve0, uint256 reserve1) = ISovereignPool(pool).getReserves();
            // Account for token0 in pool (liquid) and pending unstaking (locked)
            uint256 reserve0Total = reserve0 + IWithdrawalModule(withdrawalModule).amountToken0PendingUnstaking();
            // Account for token1 pending withdrawal to LPs (locked)
            uint256 reserve1PendingWithdrawal = IWithdrawalModule(withdrawalModule).amountToken1PendingLPWithdrawal();
            // shares calculated in terms of token1
            shares = Math.mulDiv(
                _amount,
                totalSupplyCache,
                reserve1 + IWithdrawalModule(withdrawalModule).convertToToken1(reserve0Total)
                    - reserve1PendingWithdrawal
            );
        }

        if (shares < _minShares) revert HAMM__deposit_lessThanMinShares();

        if (shares == 0) revert HAMM__deposit_zeroShares();

        _mint(_recipient, shares);

        ISovereignPool(pool).depositLiquidity(0, _amount, msg.sender, new bytes(0), abi.encode(msg.sender));
    }

    /**
     * @notice Callback to transfer tokens from user into `pool` during deposits.
     * @dev Only callable by `pool`.
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
            ERC20(token1).safeTransferFrom(user, msg.sender, _amount1);
        }
    }

    /**
     * @notice Withdraw liquidity from `pool` and burn LP tokens.
     * @param _shares Amount of LP tokens to burn.
     * @param _amount0Min Minimum amount of token0 required for `_recipient`.
     * @param _amount1Min Minimum amount of token1 required for `_recipient`.
     * @param _deadline Block timestamp after which this call reverts.
     * @param _recipient Address to receive token0 and token1 amounts.
     * @param _unwrapToNativeToken True if pool's token1 is WETH and `_recipient` wants the native token.
     * @param _isInstantWithdrawal True if user wants to swap token0 amount into token1 against the pool.
     * @return amount0 Amount of token0 withdrawn. WARNING: Potentially innacurate in case token0 is rebase.
     * @return amount1 Amount of token1 withdrawn. WARNING: Potentially innacurate in case token1 is rebase.
     */
    function withdraw(
        uint256 _shares,
        uint256 _amount0Min,
        uint256 _amount1Min,
        uint256 _deadline,
        address _recipient,
        bool _unwrapToNativeToken,
        bool _isInstantWithdrawal
    ) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        _checkDeadline(_deadline);

        if (_shares == 0) revert HAMM__withdraw_zeroShares();

        if (_recipient == address(0)) {
            revert HAMM__ZeroAddress();
        }

        (uint256 reserve0, uint256 reserve1) = ISovereignPool(pool).getReserves();

        uint256 totalSupplyCache = totalSupply();
        // Account for token1 pending withdrawal to LPs (locked)
        uint256 reserve1PendingWithdrawal = IWithdrawalModule(withdrawalModule).amountToken1PendingLPWithdrawal();
        // pro-rata share of token0 reserves in pool (liquid), token0 reserves pending in withdrawal queue (locked)
        // minus LP amount already pending withdrawal
        amount0 = Math.mulDiv(
            reserve0 + IWithdrawalModule(withdrawalModule).amountToken0PendingUnstaking()
                - IWithdrawalModule(withdrawalModule).convertToToken0(reserve1PendingWithdrawal),
            _shares,
            totalSupplyCache
        );
        // token1 amount calculated as pro-rata share of token1 reserves in the pool (liquid)
        amount1 = Math.mulDiv(reserve1, _shares, totalSupplyCache);

        // This is equivalent to an instant swap into token1, and withdraw the total amount in token1
        if (_isInstantWithdrawal) {
            uint256 amount1SwapEquivalent = getAmountOut(token0, amount0);
            amount1 += amount1SwapEquivalent;

            amount0 = 0;
        }

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
            IWithdrawalModule(withdrawalModule).burnToken0AfterWithdraw(amount0, _recipient);
        }

        // Withdraw token1 amount from pool and send to recipient,
        // also unwrapping into native token if necessary
        if (amount1 > 0) {
            ISovereignPool(pool).withdrawLiquidity(
                0, amount1, msg.sender, _unwrapToNativeToken ? address(this) : _recipient, new bytes(0)
            );

            if (_unwrapToNativeToken) {
                IWETH9(token1).withdraw(amount1);
                Address.sendValue(payable(_recipient), amount1);
            }
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
    ) external view override returns (ALMLiquidityQuote memory quote) {
        // The swap happens at 1:1 exchange rate,
        // given that the dynamic fee has already been applied
        // to the total tokenIn amount
        quote.amountInFilled = _almLiquidityQuoteInput.amountInMinusFee;

        IWithdrawalModule withdrawalModuleInterface = IWithdrawalModule(withdrawalModule);
        // token0 balances might not be 1:1 mapped to token1 balances,
        // hence we rely on the withdrawalModule to convert it (e.g., if token0 balances represent shares)
        quote.amountOut = _almLiquidityQuoteInput.isZeroToOne
            ? withdrawalModuleInterface.convertToToken1(quote.amountInFilled)
            : withdrawalModuleInterface.convertToToken0(quote.amountInFilled);
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
    ) external pure override {
        revert HAMM__onSwapCallback_NotImplemented();
    }

    /**
     *
     *  PRIVATE FUNCTIONS
     *
     */
    function _checkDeadline(uint256 deadline) private view {
        if (block.timestamp > deadline) revert HAMM___checkDeadline_expired();
    }
}
