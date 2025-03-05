// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IOverseer} from "./interfaces/IOverseer.sol";
import {IstHYPE} from "./interfaces/IstHYPE.sol";
import {IWithdrawalModule} from "./interfaces/IWithdrawalModule.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {ISTEXAMM} from "./interfaces/ISTEXAMM.sol";
import {ILendingModule} from "./interfaces/ILendingModule.sol";
import {LPWithdrawalRequest, LendingModuleProposal} from "./structs/WithdrawalModuleStructs.sol";

/**
 * @notice Withdrawal Module for integration between STEX AMM and Thunderheads' Staked Hype,
 *         and modular, upgradeable integration with a lending protocol via the Lending Module Interface.
 */
contract stHYPEWithdrawalModule is
    IWithdrawalModule,
    ReentrancyGuardTransient,
    Ownable
{
    using SafeCast for uint256;
    using SafeERC20 for IWETH9;
    using SafeERC20 for ERC20;

    /**
     *
     *  EVENTS
     *
     */
    event STEXSet(address stex);
    event LPWithdrawalRequestCreated(
        uint256 id,
        uint256 amountToken1,
        address recipient
    );
    event LPWithdrawalRequestClaimed(uint256 id);
    event LendingModuleProposed(address lendingModule, uint256 startTimestamp);
    event LendingModuleProposalCancelled();
    event LendingModuleSet(address lendingModule);
    event AmountSuppliedToLendingModule(uint256 amount);
    event AmountWithdrawnFromLendingModule(uint256 amount);

    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error stHYPEWithdrawalModule__ZeroAddress();
    error stHYPEWithdrawalModule__OnlySTEX();
    error stHYPEWithdrawalModule__OnlySTEXOrOwner();
    error stHYPEWithdrawalModule__claim_alreadyClaimed();
    error stHYPEWithdrawalModule__claim_epochIdNotProcessed();
    error stHYPEWithdrawalModule__setSTEX_AlreadySet();
    error stHYPEWithdrawalModule__withdrawToken1FromLendingPool_insufficientAmountWithdrawn();
    error stHYPEWithdrawalModule___verifyTimelockDelay_timelockTooLow();
    error stHYPEWithdrawalModule___verifyTimelockDelay_timelockTooHigh();
    error stHYPEWithdrawalModule__cancelLendingModuleProposal_ProposalNotActive();
    error stHYPEWithdrawalModule__proposeLendingModule_ProposalAlreadyActive();
    error stHYPEWithdrawalModule__setProposedLendingModule_ProposalNotActive();
    error stHYPEWithdrawalModule__setProposedLendingModule_InactiveProposal();
    error stHYPEWithdrawalModule__unstakeToken0Reserves_pendingUnstaking();
    error stHYPEWithdrawalModule__unstakeToken0Reserves_insufficientShares();
    error stHYPEWithdrawalModule__update_epochIdAlreadyProcessed();
    error stHYPEWithdrawalModule__update_invalidExchangeRate();
    error stHYPEWithdrawalModule__addClaimForPendingUnstakingShares_insufficientShares();

    /**
     *
     *  CONSTANTS
     *
     */
    uint256 private constant MIN_TIMELOCK_DELAY = 3 days;
    uint256 private constant MAX_TIMELOCK_DELAY = 7 days;

    uint256 private constant E18 = 1e18;

    /**
     *
     *  IMMUTABLES
     *
     */

    /**
     * @notice Overseer contract from Thunderheads' Liquid Staking Protocol.
     */
    address public immutable overseer;

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
     * @notice Amount of `token0` shares which are owed to STEX AMM LPs who have burnt their LP tokens.
     * @dev These amounts have not yet been unstaked.
     */
    uint256 public amountToken0SharesPendingLPWithdrawal;

    /**
     * @notice Amount of `token0` shares which are unstaking from the `overseer` withdrawal queue
     *         and are owed to STEX AMM LPs.
     */
    uint256 public amountToken0SharesUnstakingLPWithdrawal;

    /**
     * @notice Total amount of `token0` pending unstaking in the `overseer` withdrawal queue.
     */
    uint256 public amountToken0SharesPendingUnstaking;

    /**
     * @notice Unique identifier for each LP Withdrawal Request.
     */
    uint256 public idLPWithdrawal;

    /**
     * @notice Current unstaking epoch ID.
     */
    uint160 public currentEpochId;

    /**
     * @notice ID for the current unstaking epoch in the `overseer` contract.
     */
    uint256 public overseerBurnId;

    /**
     * @notice mapping from `idLPWithdrawal` to its respective `LPWithdrawalRequest` data.
     */
    mapping(uint256 => LPWithdrawalRequest) public LPWithdrawals;

    /**
     * @notice mapping from `epochId` to its respective `epochExchangeRate`.
     */
    mapping(uint256 => uint256) public epochExchangeRate;

    /**
     * @notice Address of proposed lending module to interact with lending protocol.
     */
    LendingModuleProposal public lendingModuleProposal;

    /**
     * @notice Address of lending module to interact with lending protocol.
     */
    ILendingModule public lendingModule;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _overseer, address _owner) Ownable(_owner) {
        // _lendingPool can be zero address, in case it is not set
        if (_overseer == address(0) || _owner == address(0)) {
            revert stHYPEWithdrawalModule__ZeroAddress();
        }

        overseer = _overseer;
    }

    /**
     *
     *  MODIFIERS
     *
     */
    modifier onlySTEX() {
        if (msg.sender != stex) {
            revert stHYPEWithdrawalModule__OnlySTEX();
        }
        _;
    }

    modifier onlySTEXOrOwner() {
        if (msg.sender != stex && msg.sender != owner()) {
            revert stHYPEWithdrawalModule__OnlySTEXOrOwner();
        }
        _;
    }

    /**
     *
     *  VIEW FUNCTIONS
     *
     */
    function convertToToken0(
        uint256 _amountToken1
    ) public pure override returns (uint256) {
        return _amountToken1;
    }

    function convertToToken1(
        uint256 _amountToken0
    ) public pure override returns (uint256) {
        return _amountToken0;
    }

    /**
     * @notice Returns the net amount of token0 shares in the contract.
     * @dev This is used to correct the amount of token1 in the pool.
     * @return The net amount of token0 shares in the contract.
     */
    function amount0Correction() public view override returns (int256) {
        int256 netShares = amountToken0SharesPendingUnstaking.toInt256() -
            amountToken0SharesPendingLPWithdrawal.toInt256() -
            amountToken0SharesUnstakingLPWithdrawal.toInt256();

        ISTEXAMM stexInterface = ISTEXAMM(stex);
        IstHYPE token0 = IstHYPE(stexInterface.token0());

        // > 0 means that withdrawal module owes non zero tokens to pool
        // < 0 means that pool owes tokens to withdrawal module
        return netShares * token0.sharesToBalance(E18).toInt256();
    }

    /**
     * @notice Returns the LP withdrawal request for the given `_idLPWithdrawal`.
     * @param _idLPWithdrawal The ID of the LP withdrawal request to retrieve.
     * @return The LP withdrawal request for the given ID.
     */
    function getLPWithdrawals(
        uint256 _idLPWithdrawal
    ) public view override returns (LPWithdrawalRequest memory) {
        return LPWithdrawals[_idLPWithdrawal];
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
     * @notice Sets the AMM address.
     * @dev Callable by `owner` only once.
     * @param _stex Stake Exchange AMM address to set.
     */
    function setSTEX(address _stex) external onlyOwner {
        if (_stex == address(0)) revert stHYPEWithdrawalModule__ZeroAddress();
        // Can only be set once
        if (stex != address(0)) {
            revert stHYPEWithdrawalModule__setSTEX_AlreadySet();
        }

        stex = _stex;

        emit STEXSet(_stex);
    }

    /**
     * @notice Propose a new `lendingModule`.
     * @param _lendingModule New Lending Module address to set.
     * @param _timelockDelay Timelock delay after which the proposal can be executed.
     * @dev Only callable by `owner`.
     */
    function proposeLendingModule(
        address _lendingModule,
        uint256 _timelockDelay
    ) external onlyOwner {
        _verifyTimelockDelay(_timelockDelay);

        if (lendingModuleProposal.startTimestamp > 0) {
            revert stHYPEWithdrawalModule__proposeLendingModule_ProposalAlreadyActive();
        }

        lendingModuleProposal = LendingModuleProposal({
            lendingModule: _lendingModule,
            startTimestamp: block.timestamp + _timelockDelay
        });

        emit LendingModuleProposed(
            _lendingModule,
            block.timestamp + _timelockDelay
        );
    }

    /**
     * @notice Cancel `lendingModule` proposal.
     * @dev Only callable by `owner`.
     */
    function cancelLendingModuleProposal() external onlyOwner {
        emit LendingModuleProposalCancelled();

        delete lendingModuleProposal;
    }

    /**
     * @notice Execute `lendingModule` proposal after timelock has passed.
     * @dev Only callable by `owner`.
     */
    function setProposedLendingModule() external onlyOwner {
        if (lendingModuleProposal.startTimestamp > block.timestamp) {
            revert stHYPEWithdrawalModule__setProposedLendingModule_ProposalNotActive();
        }

        if (lendingModuleProposal.startTimestamp == 0) {
            revert stHYPEWithdrawalModule__setProposedLendingModule_InactiveProposal();
        }

        if (address(lendingModule) != address(0)) {
            lendingModule.withdraw(lendingModule.assetBalance(), address(this));
        }

        lendingModule = ILendingModule(lendingModuleProposal.lendingModule);

        delete lendingModuleProposal;

        emit LendingModuleSet(address(lendingModule));
    }

    /**
     * @dev This contract will receive token1 in native form,
     *      as pending unstaking requests are processed by `overseer`.
     */
    receive() external payable {}

    /**
     * @notice This function gets called after an LP burns its LP tokens,
     *         in order to create a withdrawal request for surplus liquid token0 reserves
     *         which are yet to be unstaked via `overseer`.
     * @dev Only callable by the AMM.
     * @param _amountToken0 Amount of token0 which would be due to `_recipient`.
     * @param _recipient Address which should receive the amounts from this withdrawal's request once fulfilled.
     */
    function addClaimForPreUnstakingShares(
        uint256 _amountToken0,
        address _recipient
    ) external override onlySTEX nonReentrant {
        address token0 = ISTEXAMM(stex).token0();

        amountToken0SharesPendingLPWithdrawal += IstHYPE(token0)
            .balanceToShares(_amountToken0);

        emit LPWithdrawalRequestCreated(
            idLPWithdrawal,
            convertToToken1(_amountToken0),
            _recipient
        );

        LPWithdrawals[idLPWithdrawal] = LPWithdrawalRequest({
            recipient: _recipient,
            shares: IstHYPE(token0).balanceToShares(_amountToken0).toUint96(),
            epochId: currentEpochId
        });
        idLPWithdrawal++;
    }

    /**
     * @notice This function gets called after an LP burns its LP tokens,
     *         in order to create a withdrawal request
     *         for the token0 shares which are currently pending unstaking into token1 via `overseer`.
     * @dev Only callable by the AMM.
     * @param _shares Shares of token0 which are due to `_recipient`.
     * @param _recipient Address which should receive the amounts from this withdrawal's request once fulfilled.
     */
    function addClaimForPendingUnstakingShares(
        uint256 _shares,
        address _recipient
    ) external onlySTEX {
        // No unstaking requests have been executed
        if (currentEpochId == 0) return;

        LPWithdrawals[idLPWithdrawal] = LPWithdrawalRequest({
            recipient: _recipient,
            shares: _shares.toUint96(),
            epochId: currentEpochId - 1
        });

        idLPWithdrawal++;
        amountToken0SharesPendingLPWithdrawal += _shares;

        if (
            amountToken0SharesPendingLPWithdrawal >
            amountToken0SharesPendingUnstaking
        ) {
            revert stHYPEWithdrawalModule__addClaimForPendingUnstakingShares_insufficientShares();
        }

        emit LPWithdrawalRequestCreated(idLPWithdrawal, 0, address(this));
    }

    /**
     * @notice Claims a portion of pool's accummulated token0 reserves and executes an unstaking request (burn) via `overseer`.
     * @param _amountToken0 Amount of token0 to withdraw from pool and unstake via `overseer`.
     * @dev Only callable by `owner`.
     * @param _unstakeAmountToken0 Amount of `token0` reserves to unstake.
     */
    function unstakeToken0Reserves(
        uint256 _amountToken0
    ) external override nonReentrant onlyOwner {
        ISTEXAMM stexInterface = ISTEXAMM(stex);
        stexInterface.unstakeToken0Reserves(_amountToken0);

        address token0 = stexInterface.token0();
        uint256 amountSharesToken0 = IstHYPE(token0).sharesOf(address(this));

        // Can only execute one unstaking request at a time
        if (amountToken0SharesPendingUnstaking > 0) {
            revert stHYPEWithdrawalModule__unstakeToken0Reserves_pendingUnstaking();
        }

        // Need to unstake enough shares to cover pending LP withdrawals
        if (amountSharesToken0 < amountToken0SharesPendingLPWithdrawal) {
            revert stHYPEWithdrawalModule__unstakeToken0Reserves_insufficientShares();
        }

        amountToken0SharesPendingUnstaking = amountSharesToken0;

        amountToken0SharesUnstakingLPWithdrawal = amountToken0SharesPendingLPWithdrawal;
        amountToken0SharesPendingLPWithdrawal = 0;

        currentEpochId++;

        // Burn amountToken0 worth of token0 through withdrawal queue.
        // Once completed, an equivalent amount of native token1 should be transferred into this contract
        // depending on whether or not slashing happened.
        ERC20(token0).forceApprove(overseer, _amountToken0);
        overseerBurnId = IOverseer(overseer).burnAndRedeemIfPossible(
            address(this),
            _amountToken0,
            ""
        );
    }

    /**
     * @notice Withdraws a portion of pool's token1 reserves and supplies to `lendingModule` to earn extra yield.
     * @param _amountToken1 Amount of token1 to withdraw from pool and deposit into `lendingModule`.
     * @dev Only callable by `owner`.
     */
    function supplyToken1ToLendingPool(
        uint256 _amountToken1
    ) external onlyOwner nonReentrant {
        if (address(lendingModule) == address(0)) return;
        if (_amountToken1 == 0) return;

        ISTEXAMM stexInterface = ISTEXAMM(stex);
        stexInterface.supplyToken1Reserves(_amountToken1);

        address token1 = stexInterface.token1();

        IWETH9(token1).forceApprove(address(lendingModule), _amountToken1);

        lendingModule.deposit(_amountToken1);

        emit AmountSuppliedToLendingModule(_amountToken1);
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
    function withdrawToken1FromLendingPool(
        uint256 _amountToken1,
        address _recipient
    ) external override onlySTEXOrOwner nonReentrant {
        if (address(lendingModule) == address(0)) return;
        if (_amountToken1 == 0) return;

        address recipient = msg.sender == stex
            ? _recipient
            : ISTEXAMM(stex).pool();
        address token1 = ISTEXAMM(stex).token1();

        uint256 preBalance = ERC20(token1).balanceOf(recipient);
        lendingModule.withdraw(_amountToken1, recipient);
        uint256 postBalance = ERC20(token1).balanceOf(recipient);
        // Ensure that recipient gets at least `_amountToken1` worth of token1
        if (postBalance - preBalance < _amountToken1) {
            revert stHYPEWithdrawalModule__withdrawToken1FromLendingPool_insufficientAmountWithdrawn();
        }

        emit AmountWithdrawnFromLendingModule(_amountToken1);
    }

    /**
     * @notice Checks if the current unstaking epoch has been processed by `overseer`,
     *         and updates internal state.
     * @dev Pending LP withdrawals are prioritized,
     *      and any remaining native token is wrapped and transfered to
     *      the AMM's Sovereign Pool.
     */
    function update() external nonReentrant onlyOwner {
        // Replay protection
        if (epochExchangeRate[currentEpochId - 1] != 0)
            revert stHYPEWithdrawalModule__update_epochIdAlreadyProcessed();

        bool isBurnRedeemable = IOverseer(overseer).redeemable(overseerBurnId);
        // Check if current burn id needs to be redeemed
        if (isBurnRedeemable) {
            IOverseer(overseer).redeem(overseerBurnId);
        } else {
            // TODO: If it cannot be redeemed, we need to ensure that it has already been completed
        }

        uint256 balance = address(this).balance;

        uint256 exchangeRate = Math.mulDiv(
            balance,
            E18,
            amountToken0SharesPendingUnstaking
        );

        if (exchangeRate == 0)
            revert stHYPEWithdrawalModule__update_invalidExchangeRate();

        epochExchangeRate[currentEpochId - 1] = exchangeRate;

        uint256 amountForPool = balance -
            Math.mulDiv(
                exchangeRate,
                amountToken0SharesUnstakingLPWithdrawal,
                E18
            );

        amountToken0SharesPendingUnstaking = 0;
        amountToken0SharesUnstakingLPWithdrawal = 0;
        overseerBurnId = 0;

        ISTEXAMM stexInterface = ISTEXAMM(stex);
        address token1Address = stexInterface.token1();
        IWETH9 token1 = IWETH9(token1Address);

        // Wrap native token balance, and transfer due portion to pool
        token1.deposit{value: balance}();
        // Pool reserves are measured as balances, hence we can replenish it with token1
        // by transfering directly
        token1.safeTransfer(stexInterface.pool(), amountForPool);
    }

    /**
     * @notice Claims a LP withdrawal request which has already been fulfilled.
     * @dev Anyone can claim on behalf of its recipient.
     * @param _idLPQueue Id of LP's withdrawal request to claim.
     */
    function claim(uint256 _idLPQueue) external nonReentrant {
        LPWithdrawalRequest memory request = LPWithdrawals[_idLPQueue];

        if (request.shares == 0) {
            revert stHYPEWithdrawalModule__claim_alreadyClaimed();
        }

        if (epochExchangeRate[request.epochId] == 0) {
            revert stHYPEWithdrawalModule__claim_epochIdNotProcessed();
        }

        uint256 amountForRecipient = Math.mulDiv(
            request.shares,
            epochExchangeRate[request.epochId],
            E18
        );

        emit LPWithdrawalRequestClaimed(_idLPQueue);

        delete LPWithdrawals[_idLPQueue];

        ISTEXAMM stexInterface = ISTEXAMM(stex);

        address token1Address = stexInterface.token1();
        IWETH9(token1Address).withdraw(amountForRecipient);
        // Send equivalent amount of native token to recipient
        Address.sendValue(payable(request.recipient), amountForRecipient);
    }

    /**
     *
     *  PRIVATE FUNCTIONS
     *
     */
    function _verifyTimelockDelay(uint256 _timelockDelay) private pure {
        if (_timelockDelay < MIN_TIMELOCK_DELAY) {
            revert stHYPEWithdrawalModule___verifyTimelockDelay_timelockTooLow();
        }

        if (_timelockDelay > MAX_TIMELOCK_DELAY) {
            revert stHYPEWithdrawalModule___verifyTimelockDelay_timelockTooHigh();
        }
    }
}
