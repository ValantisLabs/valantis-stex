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
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {IWithdrawalModule} from "./interfaces/IWithdrawalModule.sol";
import {ISTEXAMM} from "./interfaces/ISTEXAMM.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {ISwapFeeModuleMinimalView} from "./interfaces/ISwapFeeModuleMinimalView.sol";
import {SwapFeeModuleProposal, WithdrawalModuleProposal} from "./structs/STEXAMMStructs.sol";

/**
 * @title Stake Exchange AMM.
 */
contract STEXAMM is ISTEXAMM, Ownable, ERC20, ReentrancyGuardTransient, Pausable {
    using SafeERC20 for ERC20;

    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error STEXAMM__OnlyPool();
    error STEXAMM__OnlyWithdrawalModule();
    error STEXAMM__ZeroAddress();
    error STEXAMM__deposit_lessThanMinShares();
    error STEXAMM__deposit_zeroShares();
    error STEXAMM__getLiquidityQuote_nonReentrant();
    error STEXAMM__onSwapCallback_NotImplemented();
    error STEXAMM__receive_onlyWETH9();
    error STEXAMM__proposeSwapFeeModule_ProposalAlreadyActive();
    error STEXAMM__setProposedSwapFeeModule_InactiveProposal();
    error STEXAMM__setProposedSwapFeeModule_Timelock();
    error STEXAMM__proposeWithdrawalModule_ProposalAlreadyActive();
    error STEXAMM__setProposedWithdrawalModule_InactiveProposal();
    error STEXAMM__setProposedWithdrawalModule_Timelock();
    error STEXAMM__unstakeToken0Reserves_amountCannotBeZero();
    error STEXAMM__unstakeToken0Reserves_amountTooHigh();
    error STEXAMM__withdraw_insufficientToken0Withdrawn();
    error STEXAMM__withdraw_insufficientToken1Withdrawn();
    error STEXAMM__withdraw_zeroShares();
    error STEXAMM___checkDeadline_expired();
    error STEXAMM___verifyTimelockDelay_timelockTooLow();
    error STEXAMM___verifyTimelockDelay_timelockTooHigh();

    /**
     *
     *  CUSTOM INTERNAL STRUCTS
     *
     */
    struct WithdrawCache {
        uint256 totalSupply;
        uint256 reserve0Pool;
        uint256 reserve1Pool;
        uint256 amount1LendingPool;
        uint256 instantWithdrawalFee1;
        uint256 amount1Remaining;
    }

    /**
     *
     *  CONSTANTS
     *
     */
    uint256 private constant BIPS = 10_000;
    uint256 private constant MINIMUM_LIQUIDITY = 1e3;

    uint256 private constant MIN_TIMELOCK_DELAY = 3 days;
    uint256 private constant MAX_TIMELOCK_DELAY = 7 days;

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
     * @notice Address of Liquid Staking token.
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
     *
     *  STORAGE
     *
     */

    /**
     * @notice Pending update proposal to Swap Fee Module.
     *         *swapFeeModule: Address of new Swap Fee Module.
     *         *startTimestamp: Block timestamp after which this proposal can be applied by `owner`.
     */
    SwapFeeModuleProposal public swapFeeModuleProposal;

    /**
     * @notice Pending update proposal to Withdrawal Module.
     *         *withdrawalModule: Address of new Withdrawal Module.
     *         *startTimestamp: Block timestamp after which this proposal can be applied by `owner`.
     */
    WithdrawalModuleProposal public withdrawalModuleProposal;

    /**
     * @notice Withdrawal Module.
     * @dev This is the module which will interface with
     *      token0's native withdrawal queue and/or token1's Lending Protocol integration.
     * @dev WARNING: This is a critical dependency which can affect the solvency of the pool.
     *      Upgrades are made under 7 days timelock and expect the `owner` to have sufficient internal security checks.
     */
    IWithdrawalModule private _withdrawalModule;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _token0,
        address _token1,
        address _swapFeeModule,
        address _protocolFactory,
        address _poolFeeRecipient1,
        address _poolFeeRecipient2,
        address _owner,
        address withdrawalModule_,
        uint256 _token0AbsErrorTolerance
    ) Ownable(_owner) ERC20(_name, _symbol) {
        if (
            _token0 == address(0) || _token1 == address(0) || _swapFeeModule == address(0)
                || _protocolFactory == address(0) || _poolFeeRecipient1 == address(0) || _poolFeeRecipient2 == address(0)
                || _owner == address(0) || withdrawalModule_ == address(0)
        ) revert STEXAMM__ZeroAddress();

        SovereignPoolConstructorArgs memory args = SovereignPoolConstructorArgs(
            _token0,
            _token1,
            _protocolFactory,
            address(this),
            address(0),
            address(0),
            true, // token0 and token1 reserves will be measured as pool's balances
            true,
            _token0AbsErrorTolerance,
            0,
            0
        );

        pool = IProtocolFactory(_protocolFactory).deploySovereignPool(args);

        ISovereignPool(pool).setSwapFeeModule(_swapFeeModule);
        ISovereignPool(pool).setALM(address(this));

        poolFeeRecipient1 = _poolFeeRecipient1;
        poolFeeRecipient2 = _poolFeeRecipient2;

        token0 = _token0;
        token1 = _token1;

        _withdrawalModule = IWithdrawalModule(withdrawalModule_);
    }

    /**
     *
     *  MODIFIERS
     *
     */
    modifier onlyPool() {
        if (msg.sender != pool) {
            revert STEXAMM__OnlyPool();
        }
        _;
    }

    modifier onlyWithdrawalModule() {
        if (msg.sender != address(_withdrawalModule)) {
            revert STEXAMM__OnlyWithdrawalModule();
        }
        _;
    }

    /**
     *
     *  VIEW FUNCTIONS
     *
     */

    /**
     * @notice Returns true if ReentrancyGuard lock is active, false otherwise.
     */
    function isLocked() external view override returns (bool) {
        return _reentrancyGuardEntered();
    }

    /**
     * @notice Returns address of Withdrawal Module.
     */
    function withdrawalModule() external view override returns (address) {
        return address(_withdrawalModule);
    }

    /**
     * @notice Helper function to estimate swap quote amounts.
     * @dev WARNING: This function has minimal internal checks,
     *      do not use for accurate simulation for `SovereignPool::swap`.
     * @param _tokenIn Address of input token to swap.
     * @param _amountIn Amount if `_tokenIn` to swap.
     * @param _isInstantWithdraw Boolean to indicate if it should be called through `withdraw`
     *         with `_isInstantWithdraw=true`.
     *        WARNING: If `_isInstantWithdraw=true`, `_amountIn` should not be accounted for fee calculation.
     * @return amountOut Amount of output token received.
     */
    function getAmountOut(address _tokenIn, uint256 _amountIn, bool _isInstantWithdraw)
        public
        view
        override
        returns (uint256 amountOut)
    {
        if ((_tokenIn != token0 && _tokenIn != token1) || _amountIn == 0) {
            return 0;
        }

        address swapFeeModule = ISovereignPool(pool).swapFeeModule();
        SwapFeeModuleData memory swapFeeData = ISwapFeeModuleMinimalView(swapFeeModule).getSwapFeeInBips(
            _tokenIn, address(0), _isInstantWithdraw ? 0 : _amountIn, address(0), new bytes(0)
        );

        uint256 amountInWithoutFee = Math.mulDiv(_amountIn, BIPS, BIPS + swapFeeData.feeInBips);
        bool isZeroToOne = _tokenIn == token0;
        // token0 balances might not be 1:1 mapped to token1 balances,
        // hence we rely on the withdrawalModule to convert it (e.g., if token0 balances represent shares)
        amountOut = isZeroToOne
            ? _withdrawalModule.convertToToken1(amountInWithoutFee)
            : _withdrawalModule.convertToToken0(amountInWithoutFee);
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */
    receive() external payable {
        if (msg.sender != token1) revert STEXAMM__receive_onlyWETH9();
    }

    /**
     * @notice Pause STEX AMM Liquidity Module.
     * @dev Only callable by `owner`.
     */
    function pause() external override onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @notice Unpause STEX AMM Liquidity Module.
     * @dev Only callable by `owner`.
     */
    function unpause() external override onlyOwner whenPaused {
        _unpause();
    }

    /**
     * @notice Propose an update to Swap Fee Module under a timelock.
     * @dev Only callable by `owner`.
     * @param _swapFeeModule Address of new Swap Fee Module to set.
     * @param _timelockDelay Timelock delay in seconds. Must be in range [3 days, 7 days].
     */
    function proposeSwapFeeModule(address _swapFeeModule, uint256 _timelockDelay) external override onlyOwner {
        if (_swapFeeModule == address(0)) revert STEXAMM__ZeroAddress();

        // An honest `owner` can propose a timelock delay greater than the minimum,
        // but no greater than the maximum
        _verifyTimelockDelay(_timelockDelay);

        if (swapFeeModuleProposal.startTimestamp > 0) {
            revert STEXAMM__proposeSwapFeeModule_ProposalAlreadyActive();
        }

        swapFeeModuleProposal =
            SwapFeeModuleProposal({swapFeeModule: _swapFeeModule, startTimestamp: block.timestamp + _timelockDelay});

        emit SwapFeeModuleProposed(_swapFeeModule, block.timestamp + _timelockDelay);
    }

    /**
     * @notice Cancel a pending update proposal to Swap Fee Module.
     * @dev Only callable by `owner`.
     */
    function cancelSwapFeeModuleProposal() external override onlyOwner {
        emit SwapFeeModuleProposalCancelled();

        delete swapFeeModuleProposal;
    }

    /**
     * @notice Set the proposed Swap Fee Module in Sovereign Pool after timelock delay.
     * @dev Only callable by `owner`.
     */
    function setProposedSwapFeeModule() external override onlyOwner {
        SwapFeeModuleProposal memory proposal = swapFeeModuleProposal;

        if (proposal.startTimestamp == 0) {
            revert STEXAMM__setProposedSwapFeeModule_InactiveProposal();
        }

        if (block.timestamp < proposal.startTimestamp) {
            revert STEXAMM__setProposedSwapFeeModule_Timelock();
        }

        ISovereignPool(pool).setSwapFeeModule(proposal.swapFeeModule);

        emit SwapFeeModuleSet(proposal.swapFeeModule);

        delete swapFeeModuleProposal;
    }

    /**
     * @notice Propose an update to Withdrawal Module under a 7 days timelock.
     * @dev Only callable by `owner`.
     * @dev WARNING: This is a critical dependency which affects the solvency of LPs,
     *      hence owner should have sufficient internal checks and protections.
     * @param withdrawalModule_ Address of new Withdrawal Module to set.
     */
    function proposeWithdrawalModule(address withdrawalModule_) external override onlyOwner {
        if (withdrawalModule_ == address(0)) revert STEXAMM__ZeroAddress();

        if (withdrawalModuleProposal.startTimestamp > 0) {
            revert STEXAMM__proposeWithdrawalModule_ProposalAlreadyActive();
        }

        withdrawalModuleProposal =
            WithdrawalModuleProposal({withdrawalModule: withdrawalModule_, startTimestamp: block.timestamp + 7 days});

        emit WithdrawalModuleProposed(withdrawalModule_, block.timestamp + 7 days);
    }

    /**
     * @notice Cancel a pending update proposal to Withdrawal Module.
     * @dev Only callable by `owner`.
     */
    function cancelWithdrawalModuleProposal() external override onlyOwner {
        emit WithdrawalModuleProposalCancelled();

        delete withdrawalModuleProposal;
    }

    /**
     * @notice Set the proposed Withdrawal Module in Sovereign Pool after a 7 days timelock delay.
     * @dev Only callable by `owner`.
     */
    function setProposedWithdrawalModule() external override onlyOwner {
        WithdrawalModuleProposal memory proposal = withdrawalModuleProposal;

        if (proposal.startTimestamp == 0) {
            revert STEXAMM__setProposedWithdrawalModule_InactiveProposal();
        }

        if (block.timestamp < proposal.startTimestamp) {
            revert STEXAMM__setProposedWithdrawalModule_Timelock();
        }

        _withdrawalModule = IWithdrawalModule(proposal.withdrawalModule);

        emit WithdrawalModuleSet(proposal.withdrawalModule);

        delete withdrawalModuleProposal;
    }

    /**
     * @notice Sets a manager/protocol fee on every swap.
     * @dev Only callable by `owner`.
     * @param _poolManagerFeeBips New pool manager fee to apply in `pool`.
     */
    function setPoolManagerFeeBips(uint256 _poolManagerFeeBips) external override onlyOwner nonReentrant {
        ISovereignPool(pool).setPoolManagerFeeBips(_poolManagerFeeBips);

        emit PoolManagerFeeSet(_poolManagerFeeBips);
    }

    /**
     * @notice Claim any accrued manager/protocol fees.
     * @dev Anyone can call this function.
     */
    function claimPoolManagerFees() external override nonReentrant {
        // WARNING: No donations should be made to this contract,
        // otherwise they will be accounted as manager fees

        // token0 fees are automatically sent to this contract (poolManager) on every swap,
        // because of SovereignPool::swap behavior for rebase input token
        uint256 fee0Received = ERC20(token0).balanceOf(address(this));
        // token1 fees are accrued on instant withdrawals
        uint256 fee1Received = ERC20(token1).balanceOf(address(this));

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

        if (fee1Received > 0) {
            uint256 fee1ToRecipient1 = fee1Received / 2;
            if (fee1ToRecipient1 > 0) {
                ERC20(token1).safeTransfer(poolFeeRecipient1, fee1ToRecipient1);
            }

            uint256 fee1ToRecipient2 = fee1Received - fee1ToRecipient1;
            if (fee1ToRecipient2 > 0) {
                ERC20(token1).safeTransfer(poolFeeRecipient2, fee1ToRecipient2);
            }
        }

        emit PoolManagerFeesClaimed(fee0Received, fee1Received);
    }

    /**
     * @notice Allows the withdrawal module to transfer a portion of `token0` reserves from `pool`
     *         and send those to the staking protocol's native withdrawal queue.
     * @dev Only callable by `withdrawalModule`.
     * @param _unstakeAmountToken0 Amount of `token0` reserves to unstake.
     */
    function unstakeToken0Reserves(uint256 _unstakeAmountToken0) external override onlyWithdrawalModule nonReentrant {
        if (_unstakeAmountToken0 == 0) {
            revert STEXAMM__unstakeToken0Reserves_amountCannotBeZero();
        }
        ISovereignPool poolInterface = ISovereignPool(pool);

        (uint256 reserve0,) = poolInterface.getReserves();
        if (_unstakeAmountToken0 > reserve0) {
            revert STEXAMM__unstakeToken0Reserves_amountTooHigh();
        }
        poolInterface.withdrawLiquidity(_unstakeAmountToken0, 0, msg.sender, msg.sender, new bytes(0));
        emit Token0ReservesUnstaked(_unstakeAmountToken0);
    }

    /**
     * @notice Allows the withdrawal module to supply a portion of `token1` reserves
     *         from `pool` into a lending protocol.
     * @dev Only callable by `withdrawalModule`.
     */
    function supplyToken1Reserves(uint256 _amount1) external override onlyWithdrawalModule nonReentrant {
        ISovereignPool(pool).withdrawLiquidity(0, _amount1, msg.sender, msg.sender, new bytes(0));
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
        whenNotPaused
        returns (uint256 shares)
    {
        _checkDeadline(_deadline);

        _withdrawalModule.update();

        uint256 totalSupplyCache = totalSupply();
        if (totalSupplyCache == 0) {
            _mint(address(1), MINIMUM_LIQUIDITY);

            shares = _amount - MINIMUM_LIQUIDITY;
        } else {
            (uint256 reserve0Pool, uint256 reserve1Pool) = ISovereignPool(pool).getReserves();
            // Account for token0 in pool (liquid) and pending unstaking (locked)
            uint256 reserve0Total = reserve0Pool + _withdrawalModule.amountToken0PendingUnstaking();
            // Account for token1 pending withdrawal to LPs (locked)
            uint256 reserve1PendingWithdrawal = _withdrawalModule.amountToken1PendingLPWithdrawal();
            // shares calculated in terms of token1
            shares = Math.mulDiv(
                _amount,
                totalSupplyCache,
                reserve1Pool + _withdrawalModule.amountToken1LendingPool()
                    + _withdrawalModule.convertToToken1(reserve0Total) - reserve1PendingWithdrawal
            );
        }

        if (shares < _minShares) revert STEXAMM__deposit_lessThanMinShares();

        if (shares == 0) revert STEXAMM__deposit_zeroShares();

        _mint(_recipient, shares);

        ISovereignPool(pool).depositLiquidity(0, _amount, msg.sender, new bytes(0), abi.encode(msg.sender));

        emit Deposit(msg.sender, _recipient, _amount, shares);
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

        if (_shares == 0) revert STEXAMM__withdraw_zeroShares();

        if (_recipient == address(0)) {
            revert STEXAMM__ZeroAddress();
        }

        _withdrawalModule.update();

        WithdrawCache memory cache;

        (cache.reserve0Pool, cache.reserve1Pool) = ISovereignPool(pool).getReserves();
        cache.totalSupply = totalSupply();

        {
            uint256 amountToken0PendingUnstaking = _withdrawalModule.amountToken0PendingUnstaking();
            uint256 reserve0PendingWithdrawal =
                _withdrawalModule.convertToToken0(_withdrawalModule.amountToken1PendingLPWithdrawal());

            uint256 amount0Deduction;
            if (cache.reserve0Pool + amountToken0PendingUnstaking > reserve0PendingWithdrawal) {
                // pro-rata share of token0 reserves in pool (liquid), token0 reserves pending in withdrawal queue (locked)
                // minus token0 amount already owed to pending LP withdrawals.
                amount0 = Math.mulDiv(
                    cache.reserve0Pool + amountToken0PendingUnstaking - reserve0PendingWithdrawal,
                    _shares,
                    cache.totalSupply
                );
            } else {
                // In this case there is more token0 owed to pending LP withdrawals,
                // but not enough token0 in pool reserves nor pending unstaking.
                // To ensure solvency of pending LP withdrawals,
                // this amount will be deducted from the user's token1 total amount (`amount1`)
                amount0Deduction = Math.mulDiv(
                    reserve0PendingWithdrawal - cache.reserve0Pool - amountToken0PendingUnstaking,
                    _shares,
                    cache.totalSupply,
                    Math.Rounding.Ceil
                );
            }

            cache.amount1LendingPool =
                Math.mulDiv(_withdrawalModule.amountToken1LendingPool(), _shares, cache.totalSupply);
            // token1 amount calculated as pro-rata share of token1 reserves in the pool (liquid)
            // plus pro-rata share of token1 reserves earning yield in lending pool (liquid, assuming lending pool allows for instant withdrawals)
            amount1 = cache.amount1LendingPool + Math.mulDiv(cache.reserve1Pool, _shares, cache.totalSupply);
            if (amount0Deduction > 0) {
                // Deduct this amount from `amount1`, as it needs to be held to honor pending LP withdrawals
                uint256 amount1Deduction = _withdrawalModule.convertToToken1(amount0Deduction);
                amount1 = amount1 > amount1Deduction ? amount1 - amount1Deduction : 0;
            }
        }

        // This is equivalent to an instant swap into token1 (with an extra fee in token1),
        // and withdraw the total amount in token1
        if (_isInstantWithdrawal) {
            uint256 amount1SwapEquivalent = getAmountOut(token0, amount0, true);
            uint256 amount1WithFee = _withdrawalModule.convertToToken1(amount0);
            // Apply manager fee on instant withdrawals in token1
            cache.instantWithdrawalFee1 =
                ((amount1WithFee - amount1SwapEquivalent) * ISovereignPool(pool).poolManagerFeeBips()) / BIPS;
            amount1 += amount1SwapEquivalent;

            amount0 = 0;
        }

        // Slippage protection checks
        if (amount0 < _amount0Min) {
            revert STEXAMM__withdraw_insufficientToken0Withdrawn();
        }
        if (amount1 < _amount1Min) {
            revert STEXAMM__withdraw_insufficientToken1Withdrawn();
        }

        // Burn LP tokens
        _burn(msg.sender, _shares);

        // Send token0 withdrawal request to withdrawal module,
        // to be processed asynchronously
        if (amount0 > 0) {
            _withdrawalModule.burnToken0AfterWithdraw(amount0, _recipient);
        }

        if (amount1 + cache.instantWithdrawalFee1 > 0) {
            // token1 amount left to withdraw
            cache.amount1Remaining = amount1 + cache.instantWithdrawalFee1;

            (, uint256 reserve1) = ISovereignPool(pool).getReserves();
            if (cache.amount1Remaining <= reserve1) {
                // If pool has enough token1 liquidity
                ISovereignPool(pool).withdrawLiquidity(
                    0, cache.amount1Remaining, msg.sender, address(this), new bytes(0)
                );
            } else {
                // If pool does not have enough token1 liquidity,
                // we withdraw full reserves from pool,
                // and attempt to withdraw remaining amount from lending pool
                ISovereignPool(pool).withdrawLiquidity(0, reserve1, msg.sender, address(this), new bytes(0));

                _withdrawalModule.withdrawToken1FromLendingPool(cache.amount1Remaining - reserve1, address(this));
            }

            // All token1 liquidity is sent to this contract beforehand,
            // so that the instant withdrawal fee can be deducted
            if (cache.amount1Remaining > cache.instantWithdrawalFee1) {
                if (_unwrapToNativeToken) {
                    IWETH9(token1).withdraw(cache.amount1Remaining - cache.instantWithdrawalFee1);
                    Address.sendValue(payable(_recipient), cache.amount1Remaining - cache.instantWithdrawalFee1);
                } else {
                    ERC20(token1).safeTransfer(_recipient, cache.amount1Remaining - cache.instantWithdrawalFee1);
                }
            }
        }

        emit Withdraw(msg.sender, _recipient, amount0, amount1, _shares);
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
    ) external view override whenNotPaused returns (ALMLiquidityQuote memory quote) {
        // Prevents read-only reentrancy via `SovereignPool::swap`,
        // while keeping `getLiquidityQuote` as read-only
        if (_reentrancyGuardEntered()) {
            revert STEXAMM__getLiquidityQuote_nonReentrant();
        }

        // The swap happens at 1:1 exchange rate,
        // given that the dynamic fee has already been applied
        // to the total tokenIn amount
        quote.amountInFilled = _almLiquidityQuoteInput.amountInMinusFee;

        // token0 balances might not be 1:1 mapped to token1 balances,
        // hence we rely on the withdrawalModule to convert it (e.g., if token0 balances represent shares)
        quote.amountOut = _almLiquidityQuoteInput.isZeroToOne
            ? _withdrawalModule.convertToToken1(quote.amountInFilled)
            : _withdrawalModule.convertToToken0(quote.amountInFilled);
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
        revert STEXAMM__onSwapCallback_NotImplemented();
    }

    /**
     *
     *  PRIVATE FUNCTIONS
     *
     */
    function _checkDeadline(uint256 deadline) private view {
        if (block.timestamp > deadline) {
            revert STEXAMM___checkDeadline_expired();
        }
    }

    function _verifyTimelockDelay(uint256 _timelockDelay) private pure {
        if (_timelockDelay < MIN_TIMELOCK_DELAY) {
            revert STEXAMM___verifyTimelockDelay_timelockTooLow();
        }

        if (_timelockDelay > MAX_TIMELOCK_DELAY) {
            revert STEXAMM___verifyTimelockDelay_timelockTooHigh();
        }
    }
}
