// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";

import {ILendingModule} from "../interfaces/ILendingModule.sol";
import {IRebalanceModule} from "../interfaces/IRebalanceModule.sol";
import {ISTEXAMM} from "../interfaces/ISTEXAMM.sol";
import {IWETH9} from "../interfaces/IWETH9.sol";
import {IWithdrawalModule} from "../interfaces/IWithdrawalModule.sol";
import {IStakingAccountant} from "../interfaces/kinetiq/IStakingAccountant.sol";
import {IStakingManager} from "../interfaces/kinetiq/IStakingManager.sol";
import {LPWithdrawalRequest, LendingModuleProposal} from "../structs/WithdrawalModuleStructs.sol";

/**
 * @notice Withdrawal Module for integration between STEX AMM and Kinetiq Liquid Staking Protocol,
 *         and modular, upgradeable integration with a lending protocol via the Lending Module Interface.
 */
contract kHYPEWithdrawalModule is IWithdrawalModule, ReentrancyGuardTransient, Ownable {
    using SafeCast for uint256;
    using SafeERC20 for IWETH9;
    using SafeERC20 for ERC20;

    /**
     *
     *  EVENTS
     *
     */
    event STEXSet(address stex);
    event LPWithdrawalRequestCreated(uint256 id, uint256 amountToken1, address recipient);
    event LPWithdrawalRequestClaimed(uint256 id);
    event LendingModuleProposed(address lendingModule, uint256 startTimestamp);
    event LendingModuleProposalCancelled();
    event LendingModuleSet(address lendingModule);
    event AmountToken1Staked(uint256 amount);
    event AmountToken0Unstaked(uint256 amount);
    event AmountSuppliedToLendingModule(uint256 amount);
    event AmountWithdrawnFromLendingModule(uint256 amount);
    event Update();
    event WithdrawalRequestConfirmed(uint256 id, uint256 amount, bool isConfirmed);
    event Sweep(address indexed token, address indexed recipient, uint256 balance);

    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error kHYPEWithdrawalModule__InvalidMaxNoBatchWithdrawals();
    error kHYPEWithdrawalModule__OnlySTEX();
    error kHYPEWithdrawalModule__OnlySTEXOrOwner();
    error kHYPEWithdrawalModule__PoolNonReentrant();
    error kHYPEWithdrawalModule__ZeroAddress();
    error kHYPEWithdrawalModule__claim_AlreadyClaimed();
    error kHYPEWithdrawalModule__claim_CannotYetClaim();
    error kHYPEWithdrawalModule__claim_InsufficientAmountToClaim();
    error kHYPEWithdrawalModule__proposeLendingModule_ProposalAlreadyActive();
    error kHYPEWithdrawalModule__rebalanceToken0Reserves_InsufficientToken1Received();
    error kHYPEWithdrawalModule__rebalanceToken0Reserves_InvalidRecipient();
    error kHYPEWithdrawalModule__rebalanceToken0Reserves_PoolToken0ReservesDecreased();
    error kHYPEWithdrawalModule__rebalanceToken0Reserves_PoolToken1ReservesDecreased();
    error kHYPEWithdrawalModule__rebalanceToken0Reserves_RebalanceModuleCallFailed();
    error kHYPEWithdrawalModule__setProposedLendingModule_InactiveProposal();
    error kHYPEWithdrawalModule__setProposedLendingModule_ProposalNotActive();
    error kHYPEWithdrawalModule__setSTEX_AlreadySet();
    error kHYPEWithdrawalModule__sweep_Token0CannotBeSweeped();
    error kHYPEWithdrawalModule__sweep_Token1CannotBeSweeped();
    error kHYPEWithdrawalModule__withdrawToken1FromLendingPool_InsufficientAmountWithdrawn();
    error kHYPEWithdrawalModule___verifyTimelockDelay_TimelockTooLow();
    error kHYPEWithdrawalModule___verifyTimelockDelay_TimelockTooHigh();

    /**
     *
     *  CONSTANTS
     *
     */
    uint256 private constant BIPS = 10_000;

    uint256 private constant MIN_TIMELOCK_DELAY = 3 days;
    uint256 private constant MAX_TIMELOCK_DELAY = 7 days;

    /**
     *
     *  IMMUTABLES
     *
     */

    /**
     * @notice Staking Accountant contract from Kinetiq Liquid Staking Protocol.
     */
    address public immutable stakingAccountant;

    /**
     * @notice Staking Manager contract from Kinetiq Liquid Staking Protocol.
     */
    address public immutable stakingManager;

    /**
     *
     *  STORAGE
     *
     */

    /**
     * @notice Address of Stake Exchange AMM (STEX AMM) deployment.
     */
    address public stex;

    /**
     * @notice Address of `stex` Sovereign Pool deployment.
     */
    address public pool;

    /**
     * @notice Amount of native `token1` which is ready for eligible STEX AMM LPs to claim.
     */
    uint256 public amountToken1ClaimableLPWithdrawal;

    /**
     * @notice Cumulative amount of native `token1` owed to LP withdrawals.
     */
    uint256 public cumulativeAmountToken1LPWithdrawal;

    /**
     * @notice Cumulative amount of native `token1` claimable by LP withdrawals.
     */
    uint256 public cumulativeAmountToken1ClaimableLPWithdrawal;

    /**
     * @notice Unique identifier for each LP Withdrawal Request.
     */
    uint256 public idLPWithdrawal;

    /**
     * @notice mapping from `idLPWithdrawal` to its respective `LPWithdrawalRequest` data.
     */
    mapping(uint256 => LPWithdrawalRequest) public LPWithdrawals;

    /**
     * @notice Address of proposed lending module to interact with lending protocol.
     * @dev WARNING: This is a critical dependency which can affect the solvency of the pool and this contract.
     *      Updates to lending module happen under a 3-7 days timelock and assumes that `owner`
     *      implements sufficient internal security checks.
     */
    LendingModuleProposal public lendingModuleProposal;

    /**
     * @notice Address of lending module to interact with lending protocol.
     */
    ILendingModule public lendingModule;

    /**
     * @notice Amount of `token0` pending unstaking in the `stakingManager` withdrawal queue.
     * @dev This might get updated after calling to `update`.
     */
    uint256 private _amountToken0PendingUnstaking;

    /**
     * @notice Amount of native `token1` which is owed to STEX AMM LPs who have burnt their LP tokens.
     * @dev This might get updated after calling to `update`.
     */
    uint256 private _amountToken1PendingLPWithdrawal;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _stakingAccountant, address _stakingManager, address _owner) Ownable(_owner) {
        if (_stakingAccountant == address(0) || _stakingManager == address(0) || _owner == address(0)) {
            revert kHYPEWithdrawalModule__ZeroAddress();
        }

        stakingAccountant = _stakingAccountant;
        stakingManager = _stakingManager;
    }

    /**
     *
     *  MODIFIERS
     *
     */
    modifier onlySTEX() {
        if (msg.sender != stex) {
            revert kHYPEWithdrawalModule__OnlySTEX();
        }
        _;
    }

    modifier onlySTEXOrOwner() {
        if (msg.sender != stex && msg.sender != owner()) {
            revert kHYPEWithdrawalModule__OnlySTEXOrOwner();
        }
        _;
    }

    modifier whenPoolNotLocked() {
        if (ISovereignPool(pool).isLocked()) {
            revert kHYPEWithdrawalModule__PoolNonReentrant();
        }
        _;
    }

    /**
     *
     *  VIEW FUNCTIONS
     *
     */

    /**
     * @notice Address of Kinetiq's protocol staking and unstaking contract.
     */
    function overseer() external view override returns (address) {
        return stakingManager;
    }

    /**
     * @notice Returns `true` if ReentrancyGuard lock is active, `false` otherwise.
     */
    function isLocked() external view override returns (bool) {
        return _reentrancyGuardEntered();
    }

    function convertToToken0(uint256 _amountToken1) public view override returns (uint256) {
        return IStakingAccountant(stakingAccountant).HYPEToKHYPE(_amountToken1);
    }

    function convertToToken1(uint256 _amountToken0) public view override returns (uint256) {
        return IStakingAccountant(stakingAccountant).kHYPEToHYPE(_amountToken0);
    }

    function token0SharesToBalance(uint256 _shares) public view override returns (uint256) {
        return convertToToken1(_shares);
    }

    function token0BalanceToShares(uint256 _balance) public view override returns (uint256) {
        return convertToToken0(_balance);
    }

    function token0SharesOf(address _account) public view override returns (uint256) {
        // token0 balances already represent shares
        return _getToken(true).balanceOf(_account);
    }

    /**
     * @notice Returns the LP withdrawal request for the given `_idLPWithdrawal`.
     * @param _idLPWithdrawal The ID of the LP withdrawal request to retrieve.
     * @return The LP withdrawal request for the given ID.
     */
    function getLPWithdrawals(uint256 _idLPWithdrawal) public view override returns (LPWithdrawalRequest memory) {
        return LPWithdrawals[_idLPWithdrawal];
    }

    /**
     * @notice Tracks amount of token0 which is pending unstaking through `stakingManager`.
     * @dev This needs to be tracked as a function of surplus native token balance in this contract,
     *      in order to maintain consistent accounting before `update` gets called
     *      and unaccounted native token balance gets transferred.
     */
    function amountToken0PendingUnstaking() public view override returns (uint256) {
        uint256 excessToken1 = _getExcessNativeBalance();
        uint256 excessToken0 = convertToToken0(excessToken1);

        uint256 amountToken0PendingUnstakingCache = _amountToken0PendingUnstaking;
        if (amountToken0PendingUnstakingCache > excessToken0) {
            return amountToken0PendingUnstakingCache - excessToken0;
        } else {
            return 0;
        }
    }

    /**
     * @notice Similar to `amountToken0PendingUnstaking()`,
     *         but returns the value in storage prior to calling `update`.
     */
    function amountToken0PendingUnstakingBeforeUpdate() external view override returns (uint256) {
        return _amountToken0PendingUnstaking;
    }

    /**
     * @notice Tracks amount of token1 which is owed to LP withdrawal requests.
     * @dev This needs to be tracked as a function of surplus native token balance in this contract,
     *      in order to maintain consistent accounting before `update` gets called.
     */
    function amountToken1PendingLPWithdrawal() public view override returns (uint256) {
        uint256 excessNativeBalance = _getExcessNativeBalance();

        uint256 amountToken1PendingLPWithdrawalCache = _amountToken1PendingLPWithdrawal;
        if (amountToken1PendingLPWithdrawalCache > excessNativeBalance) {
            return amountToken1PendingLPWithdrawalCache - excessNativeBalance;
        } else {
            return 0;
        }
    }

    /**
     * @notice Similar to `amountToken1PendingLPWithdrawal()`,
     *         but returns the value in storage prior to calling `update`.
     */
    function amountToken1PendingLPWithdrawalBeforeUpdate() external view override returns (uint256) {
        return _amountToken1PendingLPWithdrawal;
    }

    /**
     * @notice Returns amount of token1 owned in the lending module.
     */
    function amountToken1LendingPool() public view override returns (uint256) {
        if (address(lendingModule) != address(0)) {
            // Returns balance of underlying token (token1) in the Lending Module's lending protocol position
            return lendingModule.assetBalance();
        } else {
            return 0;
        }
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Sets the STEX AMM address and respective Sovereign Pool deployment.
     * @dev Callable by `owner` only once.
     * @param _stex Stake Exchange AMM address to set.
     */
    function setSTEX(address _stex) external onlyOwner {
        if (_stex == address(0)) revert kHYPEWithdrawalModule__ZeroAddress();
        // Can only be set once
        if (stex != address(0)) {
            revert kHYPEWithdrawalModule__setSTEX_AlreadySet();
        }

        stex = _stex;
        pool = ISTEXAMM(_stex).pool();

        emit STEXSet(_stex);
    }

    /**
     * @notice Sweep token balances which have been locked into this contract.
     * @dev Only callable by `owner`.
     * @param _token Token address to claim balances for.
     * @param _recipient Recipient of `_token` balance.
     */
    function sweep(address _token, address _recipient) external onlyOwner {
        if (_token == address(0)) revert kHYPEWithdrawalModule__ZeroAddress();
        if (_recipient == address(0)) {
            revert kHYPEWithdrawalModule__ZeroAddress();
        }

        if (_token == ISTEXAMM(stex).token0()) {
            revert kHYPEWithdrawalModule__sweep_Token0CannotBeSweeped();
        }
        if (_token == ISTEXAMM(stex).token1()) {
            revert kHYPEWithdrawalModule__sweep_Token1CannotBeSweeped();
        }

        uint256 balance = ERC20(_token).balanceOf(address(this));
        if (balance > 0) {
            ERC20(_token).safeTransfer(_recipient, balance);

            emit Sweep(_token, _recipient, balance);
        }
    }

    /**
     * @notice Propose an update to Lending Module.
     * @dev Only callable by `owner`.
     * @dev WARNING: This is a critical dependency which affects the solvency of the pool and this contract,
     *      hence `owner` should have sufficient internal checks and protections.
     * @param _lendingModule Address of new Lending Module to set.
     * @param _timelockDelay 3-7 days timelock delay.
     */
    function proposeLendingModule(address _lendingModule, uint256 _timelockDelay) external onlyOwner {
        _verifyTimelockDelay(_timelockDelay);

        if (lendingModuleProposal.startTimestamp > 0) {
            revert kHYPEWithdrawalModule__proposeLendingModule_ProposalAlreadyActive();
        }

        lendingModuleProposal =
            LendingModuleProposal({lendingModule: _lendingModule, startTimestamp: block.timestamp + _timelockDelay});

        emit LendingModuleProposed(_lendingModule, block.timestamp + _timelockDelay);
    }

    /**
     * @notice Cancel a pending update proposal to Lending Module.
     * @dev Only callable by `owner`.
     */
    function cancelLendingModuleProposal() external onlyOwner {
        emit LendingModuleProposalCancelled();

        delete lendingModuleProposal;
    }

    /**
     * @notice Set the proposed Lending Module after timelock has passed.
     * @dev Only callable by `owner`.
     */
    function setProposedLendingModule() external onlyOwner whenPoolNotLocked {
        if (lendingModuleProposal.startTimestamp > block.timestamp) {
            revert kHYPEWithdrawalModule__setProposedLendingModule_ProposalNotActive();
        }

        if (lendingModuleProposal.startTimestamp == 0) {
            revert kHYPEWithdrawalModule__setProposedLendingModule_InactiveProposal();
        }

        // Withdraw all token1 amount from lending module back into pool
        if (address(lendingModule) != address(0)) {
            uint256 amountToken1LendingModule = lendingModule.assetBalance();

            if (amountToken1LendingModule > 0) {
                lendingModule.withdraw(amountToken1LendingModule, pool);
            }
        }

        // Set new lending module
        lendingModule = ILendingModule(lendingModuleProposal.lendingModule);

        // Sanity check that it is possible to query `assetBalance` from the new lending module
        lendingModule.assetBalance();

        delete lendingModuleProposal;

        emit LendingModuleSet(address(lendingModule));
    }

    /**
     * @dev This contract will receive token1 in native form,
     *      as pending unstaking requests are settled.
     */
    receive() external payable {}

    /**
     * @notice This function gets called after an LP burns its LP tokens,
     *         in order to create a pending request.
     * @dev Only callable by the AMM.
     * @param _amountToken0 Amount of token0 which would be due to `_recipient`.
     * @param _recipient Address which should receive the amounts from this withdrawal's request once fulfilled.
     */
    function burnToken0AfterWithdraw(uint256 _amountToken0, address _recipient)
        external
        override
        onlySTEX
        nonReentrant
    {
        IStakingManager stakingManagerInterface = IStakingManager(stakingManager);

        uint256 feeToken0Bips = stakingManagerInterface.unstakeFeeRate();

        // `stakingManager` charges an unstaking fee in token0
        uint256 feeToken0 = Math.mulDiv(_amountToken0, feeToken0Bips, BIPS);

        // Amount of token1 which the LP expects to receive after unstaking,
        // excluding token0 fee and assuming no slashing
        uint256 amountToken1 = convertToToken1(_amountToken0 - feeToken0);

        _amountToken1PendingLPWithdrawal += amountToken1;

        emit LPWithdrawalRequestCreated(idLPWithdrawal, amountToken1, _recipient);

        LPWithdrawals[idLPWithdrawal] = LPWithdrawalRequest({
            recipient: _recipient,
            amountToken1: amountToken1.toUint96(),
            cumulativeAmountToken1LPWithdrawalCheckpoint: cumulativeAmountToken1LPWithdrawal
        });
        idLPWithdrawal++;

        cumulativeAmountToken1LPWithdrawal += amountToken1;
    }

    /**
     * @notice This function gets called by either:
     *         - AMM, after an LP burns its LP tokens,
     *           in order to withdraw `token1` amounts from the lending protocol.
     *         - `owner`, to withdraw `token1` from lending protocol back into pool.
     * @dev Only callable by the AMM or `owner`.
     * @param _amountToken1 Amount of token1 which is due to `_recipient` or pool.
     * @param _recipient Address which should receive `_amountToken1` of `token1`,
     *                   only relevant if msg.sender == AMM.
     */
    function withdrawToken1FromLendingPool(uint256 _amountToken1, address _recipient)
        external
        override
        onlySTEXOrOwner
        nonReentrant
        whenPoolNotLocked
    {
        if (address(lendingModule) == address(0)) return;
        if (_amountToken1 == 0) return;

        address recipient = msg.sender == stex ? _recipient : pool;
        ERC20 token1 = _getToken(false);

        uint256 preBalance = token1.balanceOf(recipient);
        lendingModule.withdraw(_amountToken1, recipient);
        uint256 postBalance = token1.balanceOf(recipient);
        // Ensure that recipient gets at least `_amountToken1` worth of token1
        if (postBalance - preBalance < _amountToken1) {
            revert kHYPEWithdrawalModule__withdrawToken1FromLendingPool_InsufficientAmountWithdrawn();
        }

        emit AmountWithdrawnFromLendingModule(_amountToken1);
    }

    /**
     * @notice Withdraws a portion of pool's token1 reserves and stakes into `stakingManager` for an equivalent amount of `token0`.
     * @dev Only callable by `owner`.
     * @param _amountToken1 Amount of pool's token1 reserves to stake into token0.
     */
    function stakeToken1(uint256 _amountToken1) external onlyOwner whenPoolNotLocked nonReentrant {
        if (_amountToken1 == 0) return;

        ISTEXAMM stexInterface = ISTEXAMM(stex);
        stexInterface.supplyToken1Reserves(_amountToken1);

        // Unwrap into native token
        _getWrappedNativeToken().withdraw(_amountToken1);

        // Stake `_amounToken1` of token1 into token0
        ERC20 token0 = _getToken(true);
        uint256 token0PreBalance = token0.balanceOf(address(this));
        IStakingManager(stakingManager).stake{value: _amountToken1}();
        uint256 amountToken0 = token0.balanceOf(address(this)) - token0PreBalance;

        // Transfer minted LST balance to STEX AMM's pool
        token0.safeTransfer(pool, amountToken0);

        emit AmountToken1Staked(_amountToken1);
    }

    /**
     * @notice Withdraws a portion of pool's token1 reserves,
     *         unwraps into native token to net against pending LP withdrawals,
     *         and transfers any left-over back into the pool.
     * @dev Only callable by `owner`.
     * @param _amountToken1 Amount of pool's token1 reserves to stake into token0.
     */
    function settlePendingWithdrawalsWithPoolReserves(uint256 _amountToken1)
        external
        onlyOwner
        nonReentrant
        whenPoolNotLocked
    {
        if (_amountToken1 == 0) return;

        // Ensure that net new native token balance is properly accounted for
        _update(false);

        ISTEXAMM(stex).supplyToken1Reserves(_amountToken1);

        // Unwrap into native token
        _getWrappedNativeToken().withdraw(_amountToken1);

        // Use native token balance to net against pending LP withdrawals,
        // and transfer left-over amount as token1 back into pool
        _update(true);
    }

    /**
     * @notice Withdraws a portion of pool's token1 reserves and supplies to `lendingPool` to earn extra yield.
     * @dev Only callable by `owner`.
     * @param _amountToken1 Amount of token1 reserves to supply.
     */
    function supplyToken1ToLendingPool(uint256 _amountToken1) external override onlyOwner nonReentrant {
        if (address(lendingModule) == address(0)) return;
        if (_amountToken1 == 0) return;

        ISTEXAMM(stex).supplyToken1Reserves(_amountToken1);

        ERC20 token1 = _getToken(false);

        token1.forceApprove(address(lendingModule), _amountToken1);
        // WARNING: Assumes that lending module deposits the total `_amountToken1` (no partial deposits)
        lendingModule.deposit(_amountToken1);

        emit AmountSuppliedToLendingModule(_amountToken1);
    }

    /**
     * @notice Claims pool's accummulated token0 reserves and executes an unstaking request (burn) via `stakingManager`.
     * @dev Only callable by `owner`.
     * @param _unstakeAmountToken0 Amount of `token0` reserves to unstake.
     */
    function unstakeToken0Reserves(uint256 _unstakeAmountToken0) external override nonReentrant onlyOwner {
        _unstakeToken0Reserves(_unstakeAmountToken0);
    }

    /**
     * @notice Atomically rebalances excess token0 reserves into token1,
     *         at a price no worse than using `stakingManager` withdrawal queue.
     * @dev Only callable by `owner`.
     * @param _amountToken0 Amount of token0 reserves to rebalance into token1.
     * @param _recipient Address to receive `_amountToken0` of token0.
     * @param _rebalanceModule Address which should execute the rebalance.
     *        If zero, it assumes that `owner` will provide the token1 amount.
     * @param _payload payload to `_rebalanceModule`.
     */
    function rebalanceToken0Reserves(
        uint256 _amountToken0,
        address _recipient,
        address _rebalanceModule,
        bytes calldata _payload
    ) external nonReentrant onlyOwner whenPoolNotLocked {
        if (_recipient == address(0)) {
            revert kHYPEWithdrawalModule__ZeroAddress();
        }
        // If `_rebalanceModule` is specified,
        // it must also be the recipient of token0
        if (_rebalanceModule != address(0) && _recipient != _rebalanceModule) {
            revert kHYPEWithdrawalModule__rebalanceToken0Reserves_InvalidRecipient();
        }

        if (_amountToken0 == 0) return;

        ISTEXAMM(stex).unstakeToken0Reserves(_amountToken0);

        // Kinetiq charges an unstaking fee
        uint256 feeToken0 = Math.mulDiv(_amountToken0, IStakingManager(stakingManager).unstakeFeeRate(), BIPS);
        // The rebalance must return at least the amount of token1
        // which would be received by going through `stakingManager`
        uint256 amountToken1Min = convertToToken1(_amountToken0 - feeToken0);

        ERC20 token0 = _getToken(true);
        ERC20 token1 = _getToken(false);

        // Transfer token0 amount to `_recipient`
        token0.safeTransfer(_recipient, _amountToken0);

        (uint256 preReserve0, uint256 preReserve1) = ISovereignPool(pool).getReserves();
        uint256 preToken1Balance = token1.balanceOf(address(this));
        if (_rebalanceModule == address(0)) {
            // msg.sender should have approved this contract to transfer
            // `amountToken1Min` worth of token1
            token1.safeTransferFrom(msg.sender, address(this), amountToken1Min);
        } else {
            // General callback for `_rebalanceModule` to swap token0 into token1
            bytes4 selector = IRebalanceModule(_rebalanceModule).rebalance(amountToken1Min, _payload);
            if (selector != IRebalanceModule.rebalance.selector) {
                revert kHYPEWithdrawalModule__rebalanceToken0Reserves_RebalanceModuleCallFailed();
            }
        }
        (uint256 postReserve0, uint256 postReserve1) = ISovereignPool(pool).getReserves();

        // Ensure that pool reserves have not decreased after rebalancing
        if (postReserve0 < preReserve0) {
            revert kHYPEWithdrawalModule__rebalanceToken0Reserves_PoolToken0ReservesDecreased();
        }

        if (postReserve1 < preReserve1) {
            revert kHYPEWithdrawalModule__rebalanceToken0Reserves_PoolToken1ReservesDecreased();
        }

        uint256 amountToken1Received = token1.balanceOf(address(this)) - preToken1Balance;
        // Ensure that enough token1 amount has been received
        if (amountToken1Received < amountToken1Min) {
            revert kHYPEWithdrawalModule__rebalanceToken0Reserves_InsufficientToken1Received();
        }

        // Transfer received token1 amount to pool
        token1.safeTransfer(pool, amountToken1Received);
    }

    /**
     * @notice Unstakes left-over token0 balance in this contract.
     * @dev This can happen in case of token0 donations, or Kinetiq withdrawal cancellations.
     * @dev Only callable by `owner`.
     */
    function unstakeExcessToken0() external nonReentrant onlyOwner {
        ERC20 token0 = _getToken(true);
        uint256 token0Balance = token0.balanceOf(address(this));

        if (token0Balance == 0) return;

        _unstakeToken0(token0Balance);
    }

    /**
     * @notice Allows anyone to claim a processed withdrawal id from `stakingManager`.
     * @param _id Id of withdrawal to confirm in `stakingManager`.
     * @return isConfirmed Boolean that indicates if the request got processed by this function call.
     */
    function confirmWithdrawal(uint256 _id) external nonReentrant whenPoolNotLocked returns (bool isConfirmed) {
        isConfirmed = _confirmWithdrawal(_id);

        // Update accounting state immediately after confirmation
        if (isConfirmed) {
            _update(false);
        }
    }

    /**
     * @notice Checks current balance of native token and updates state.
     * @dev Pending LP withdrawals are prioritized,
     *      and any remaining native token is wrapped and transfered to
     *      the AMM's Sovereign Pool.
     */
    function update() external override nonReentrant whenPoolNotLocked {
        _update(false);
    }

    /**
     * @notice Claims a LP withdrawal request which has already been fulfilled.
     * @dev Anyone can claim on behalf of its recipient.
     * @param _idLPQueue Id of LP's withdrawal request to claim.
     */
    function claim(uint256 _idLPQueue) external override nonReentrant whenPoolNotLocked {
        // WARNING: This implementation assumes that there is no slashing enabled in the LST protocol

        LPWithdrawalRequest memory request = LPWithdrawals[_idLPQueue];

        // Check if LP withdrawal has already been claimed
        if (request.amountToken1 == 0) {
            revert kHYPEWithdrawalModule__claim_AlreadyClaimed();
        }

        // Check if there is enough native token available to fulfill the rest of this request
        if (amountToken1ClaimableLPWithdrawal < request.amountToken1) {
            revert kHYPEWithdrawalModule__claim_InsufficientAmountToClaim();
        }

        // Check if it is the right time to claim (according to queue priority)
        if (
            cumulativeAmountToken1ClaimableLPWithdrawal
                < request.cumulativeAmountToken1LPWithdrawalCheckpoint + request.amountToken1
        ) {
            revert kHYPEWithdrawalModule__claim_CannotYetClaim();
        }

        amountToken1ClaimableLPWithdrawal -= request.amountToken1;

        emit LPWithdrawalRequestClaimed(_idLPQueue);

        delete LPWithdrawals[_idLPQueue];

        // Send equivalent amount of native token to recipient
        Address.sendValue(payable(request.recipient), request.amountToken1);
    }

    /**
     *
     *  PRIVATE FUNCTIONS
     *
     */
    function _update(bool isPoolRebalance) private {
        // WARNING: This implementation assumes that there is no slashing enabled in the LST protocol

        // `confirmWithdrawal` should be called in order to process confirmed withdrawals
        // and accrue net new native token balance to this contract

        // Need to ensure that enough native token is reserved for settled LP withdrawals
        uint256 excessNativeBalance = _getExcessNativeBalance();
        if (excessNativeBalance == 0) return;

        if (!isPoolRebalance) {
            uint256 amountToken0PendingUnstakingCache = _amountToken0PendingUnstaking;
            uint256 excessToken0Balance = convertToToken0(excessNativeBalance);
            if (amountToken0PendingUnstakingCache > excessToken0Balance) {
                _amountToken0PendingUnstaking = amountToken0PendingUnstakingCache - excessToken0Balance;
            } else {
                _amountToken0PendingUnstaking = 0;
            }
        }

        // Allocate native token balance to pending LP withdrawal requests
        uint256 amountToken1PendingLPWithdrawalCache = _amountToken1PendingLPWithdrawal;
        if (excessNativeBalance > amountToken1PendingLPWithdrawalCache) {
            excessNativeBalance -= amountToken1PendingLPWithdrawalCache;
            amountToken1ClaimableLPWithdrawal += amountToken1PendingLPWithdrawalCache;
            cumulativeAmountToken1ClaimableLPWithdrawal += amountToken1PendingLPWithdrawalCache;
            _amountToken1PendingLPWithdrawal = 0;
        } else {
            _amountToken1PendingLPWithdrawal -= excessNativeBalance;
            amountToken1ClaimableLPWithdrawal += excessNativeBalance;
            cumulativeAmountToken1ClaimableLPWithdrawal += excessNativeBalance;
            excessNativeBalance = 0;

            emit Update();

            return;
        }

        // Wrap left-over native token into token1 and re-deposit into the pool
        IWETH9 token1 = _getWrappedNativeToken();

        token1.deposit{value: excessNativeBalance}();
        // Pool reserves are measured as balances, hence we can replenish it with token1
        // by transfering directly
        token1.safeTransfer(pool, excessNativeBalance);

        emit Update();
    }

    function _confirmWithdrawal(uint256 id) private returns (bool isConfirmed) {
        IStakingManager.WithdrawalRequest memory request =
            IStakingManager(stakingManager).withdrawalRequests(address(this), id);

        // Request does not exist, has been cancelled,
        // or has already been confirmed
        if (request.hypeAmount == 0) return false;

        // Request is not yet ready to claim
        if (block.timestamp < request.timestamp + IStakingManager(stakingManager).withdrawalDelay()) {
            return false;
        }

        uint256 preBalance = address(this).balance;

        IStakingManager(stakingManager).confirmWithdrawal(id);

        isConfirmed = address(this).balance >= preBalance + request.hypeAmount;

        emit WithdrawalRequestConfirmed(id, request.hypeAmount, isConfirmed);
    }

    function _unstakeToken0Reserves(uint256 amountToken0) private {
        ISTEXAMM(stex).unstakeToken0Reserves(amountToken0);

        // Kinetiq charges an unstaking fee
        uint256 feeToken0 = Math.mulDiv(amountToken0, IStakingManager(stakingManager).unstakeFeeRate(), BIPS);

        _amountToken0PendingUnstaking += (amountToken0 - feeToken0);

        _unstakeToken0(amountToken0);
    }

    function _unstakeToken0(uint256 amountToken0) private {
        // Burn `amountToken0` worth of token0 through `stakingManager` withdrawal queue.
        // WARNING: This implementation assumes that there is no slashing enabled in the LST protocol
        _getToken(true).forceApprove(stakingManager, amountToken0);
        IStakingManager(stakingManager).queueWithdrawal(amountToken0);

        emit AmountToken0Unstaked(amountToken0);
    }

    function _getToken(bool isToken0) private view returns (ERC20 token) {
        return isToken0 ? ERC20(ISTEXAMM(stex).token0()) : ERC20(ISTEXAMM(stex).token1());
    }

    function _getWrappedNativeToken() private view returns (IWETH9 token) {
        return IWETH9(ISTEXAMM(stex).token1());
    }

    function _getExcessNativeBalance() private view returns (uint256) {
        // Calculates native token balance in excess of the balance already claimable by processed LP withdrawals
        // This will be used to net against pending LP withdrawals, and any leftover can be transferred
        // to STEX AMM's pool via `update`
        uint256 balanceNative = address(this).balance;
        uint256 excessBalanceNative =
            balanceNative > amountToken1ClaimableLPWithdrawal ? balanceNative - amountToken1ClaimableLPWithdrawal : 0;

        return excessBalanceNative;
    }

    function _verifyTimelockDelay(uint256 _timelockDelay) private pure {
        if (_timelockDelay < MIN_TIMELOCK_DELAY) {
            revert kHYPEWithdrawalModule___verifyTimelockDelay_TimelockTooLow();
        }

        if (_timelockDelay > MAX_TIMELOCK_DELAY) {
            revert kHYPEWithdrawalModule___verifyTimelockDelay_TimelockTooHigh();
        }
    }
}
