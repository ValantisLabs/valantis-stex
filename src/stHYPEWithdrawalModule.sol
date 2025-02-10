// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IOverseer} from "./interfaces/IOverseer.sol";
import {IstHYPE} from "./interfaces/IstHYPE.sol";
import {IWithdrawalModule} from "./interfaces/IWithdrawalModule.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {ISTEXAMM} from "./interfaces/ISTEXAMM.sol";
import {IPool} from "./interfaces/aavev3/IPool.sol";
import {LPWithdrawalRequest} from "./structs/WithdrawalModuleStructs.sol";

/**
 * @notice Withdrawal Module for integration between STEX AMM and Thunderheads' Staked Hype.
 */
contract stHYPEWithdrawalModule is IWithdrawalModule, ReentrancyGuardTransient, Ownable {
    using SafeCast for uint256;
    using SafeERC20 for IWETH9;

    /**
     *
     *  EVENTS
     *
     */
    event STEXSet(address stex);
    event LPWithdrawalRequestCreated(uint256 id, uint256 amountToken1, address recipient);
    event LPWithdrawalRequestClaimed(uint256 id);

    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error stHYPEWithdrawalModule__ZeroAddress();
    error stHYPEWithdrawalModule__OnlyInitializer();
    error stHYPEWithdrawalModule__OnlySTEX();
    error stHYPEWithdrawalModule__OnlySTEXOrOwner();
    error stHYPEWithdrawalModule__claim_alreadyClaimed();
    error stHYPEWithdrawalModule__claim_cannotYetClaim();
    error stHYPEWithdrawalModule__claim_insufficientAmountToClaim();
    error stHYPEWithdrawalModule__setSTEX_AlreadySet();

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
     * @notice Address to interact with a Lending Protocol, assuming AAVE V3 interface.
     */
    address public immutable lendingPool;

    /**
     * @notice AAVE V3's interface aWETH address.
     */
    address public immutable lendingPoolYieldToken;

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
     * @notice Amount of native `token1` which is owed to STEX AMM LPs who have burnt their LP tokens.
     */
    uint256 public amountToken1PendingLPWithdrawal;

    /**
     * @notice Amount of native `token1` which is ready for eligible STEX AMM LPs to claim.
     */
    uint256 public amountToken1ClaimableLPWithdrawal;

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
     * @notice Amount of `token0` pending unstaking in the `overseer` withdrawal queue.
     */
    uint256 private _amountToken0PendingUnstaking;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _overseer, address _lendingPool, address _lendingPoolYieldToken, address _owner)
        Ownable(_owner)
    {
        // _lendingPool can be zero address, in case it is not set
        if (_overseer == address(0) || _owner == address(0)) {
            revert stHYPEWithdrawalModule__ZeroAddress();
        }

        overseer = _overseer;
        lendingPool = _lendingPool;
        lendingPoolYieldToken = _lendingPoolYieldToken;
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
    function convertToToken0(uint256 _amountToken1) public view override returns (uint256) {
        address token0 = ISTEXAMM(stex).token0();
        return IstHYPE(token0).assetsToShares(_amountToken1);
    }

    function convertToToken1(uint256 _amountToken0) public view override returns (uint256) {
        address token0 = ISTEXAMM(stex).token0();
        return IstHYPE(token0).sharesToAssets(_amountToken0);
    }

    /**
     * @notice Tracks amount of token0 which is pending unstaking through `overseer`.
     * @dev It is assumed that `overseer` will replenish this contract with native token as
     *      unstaking requests get fulfilled.
     */
    function amountToken0PendingUnstaking() public view override returns (uint256) {
        uint256 balanceNative = address(this).balance;
        uint256 excessNative =
            balanceNative > amountToken1ClaimableLPWithdrawal ? balanceNative - amountToken1ClaimableLPWithdrawal : 0;
        uint256 excessToken0 = excessNative > 0 ? convertToToken0(excessNative) : 0;

        uint256 amountToken0PendingUnstakingCache = _amountToken0PendingUnstaking;
        if (amountToken0PendingUnstakingCache > excessToken0) {
            return amountToken0PendingUnstakingCache - excessToken0;
        } else {
            return 0;
        }
    }

    /**
     * @notice Returns amount of token1 owned by this position in the lending pool, including any yield accrued.
     */
    function amountToken1LendingPool() public view override returns (uint256) {
        if (lendingPoolYieldToken != address(0)) {
            // Returns balance of aToken
            return ERC20(lendingPoolYieldToken).balanceOf(address(this));
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
     * @dev This contract will receive token1 in native form,
     *      as pending unstaking requests are settled.
     */
    receive() external payable nonReentrant {}

    /**
     * @notice This function gets called after an LP burns its LP tokens,
     *         in order to create a pending request
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
        // stHYPE's balances represent shares,
        // so we need to calculate the equivalent amount expected in token1 (equivalently, native token)
        uint256 amountToken1 = convertToToken1(_amountToken0);

        amountToken1PendingLPWithdrawal += amountToken1;

        emit LPWithdrawalRequestCreated(idLPWithdrawal, amountToken1, _recipient);

        LPWithdrawals[idLPWithdrawal] = LPWithdrawalRequest({
            recipient: _recipient,
            amountToken1: amountToken1.toUint96(),
            cumulativeAmountToken1ClaimableLPWithdrawalCheckpoint: cumulativeAmountToken1ClaimableLPWithdrawal
        });
        idLPWithdrawal++;
    }

    /**
     * @notice This function gets called after an LP burns its LP tokens,
     *         in order to withdraw `token1` amounts from the lending protocol.
     * @dev Only callable by the AMM or `owner`.
     * @dev `owner` can only withdraw from lending pool into AMM's Sovereign Pool.
     * @param _amountToken1 Amount of token1 which is due to `_recipient`.
     * @param _recipient Address which should receive `_amountToken1` of `token1`.
     */
    function withdrawToken1FromLendingPool(uint256 _amountToken1, address _recipient)
        external
        override
        onlySTEXOrOwner
        nonReentrant
    {
        if (lendingPool == address(0)) return;

        IPool(lendingPool).withdraw(
            ISTEXAMM(stex).token1(), _amountToken1, msg.sender == stex ? _recipient : ISTEXAMM(stex).pool()
        );
    }

    /**
     * @notice Withdraws a portion of pool's token1 reserves and supplies to `lendingPool` to earn extra yield.
     * @dev Only callable by `owner`.
     */
    function supplyToken1ToLendingPool(uint256 _amountToken1) external onlyOwner nonReentrant {
        if (lendingPool == address(0)) return;
        if (_amountToken1 == 0) return;

        ISTEXAMM stexInterface = ISTEXAMM(stex);
        stexInterface.supplyToken1Reserves(_amountToken1);

        address token1 = stexInterface.token1();

        IWETH9(token1).forceApprove(lendingPool, _amountToken1);

        IPool(lendingPool).supply(token1, _amountToken1, address(this), 0);
    }

    /**
     * @notice Claims pool's accummulated token0 reserves and executes an unstaking request (burn) via `overseer`.
     * @dev Only callable by `owner`.
     */
    function unstakeToken0Reserves() external override nonReentrant onlyOwner {
        ISTEXAMM stexInterface = ISTEXAMM(stex);
        stexInterface.unstakeToken0Reserves();

        address token0 = stexInterface.token0();
        uint256 amountToken0 = IstHYPE(token0).balanceOf(address(this));

        _amountToken0PendingUnstaking += amountToken0;

        // Burn amountToken0 worth of token0 through withdrawal queue.
        // Once completed, an equivalent amount of native token1 should be transferred into this contract
        // WARNING: token0 balances represent shares,
        // hence the equivalent amount of token1 to be received is not 1:1
        IOverseer(overseer).burn(address(this), amountToken0);
    }

    /**
     * @notice Checks current balance of native token and updates state.
     * @dev Pending LP withdrawals are prioritized,
     *      and any remaining native token is wrapped and transfered to
     *      the AMM's Sovereign Pool.
     */
    function update() external nonReentrant {
        // Need to ensure that enough native token is reserved for settled LP withdrawals
        uint256 amountToken1ClaimableLPWithdrawalCache = amountToken1ClaimableLPWithdrawal;
        if (address(this).balance <= amountToken1ClaimableLPWithdrawalCache) {
            return;
        }

        // Having a surplus balance of native token means that new unstaking requests have been fulfilled
        uint256 balanceSurplus = address(this).balance - amountToken1ClaimableLPWithdrawalCache;
        uint256 balanceSurplusToken0 = convertToToken0(balanceSurplus);

        uint256 amountToken0PendingUnstakingCache = _amountToken0PendingUnstaking;
        if (amountToken0PendingUnstakingCache > balanceSurplusToken0) {
            _amountToken0PendingUnstaking = amountToken0PendingUnstakingCache - balanceSurplusToken0;
        } else {
            _amountToken0PendingUnstaking = 0;
        }

        // Prioritize LP withdrawal requests
        uint256 amountToken1PendingLPWithdrawalCache = amountToken1PendingLPWithdrawal;
        if (balanceSurplus > amountToken1PendingLPWithdrawalCache) {
            balanceSurplus -= amountToken1PendingLPWithdrawalCache;
            amountToken1ClaimableLPWithdrawal += amountToken1PendingLPWithdrawalCache;
            cumulativeAmountToken1ClaimableLPWithdrawal += amountToken1PendingLPWithdrawalCache;
            amountToken1PendingLPWithdrawal = 0;
        } else {
            amountToken1PendingLPWithdrawal -= balanceSurplus;
            amountToken1ClaimableLPWithdrawal += balanceSurplus;
            cumulativeAmountToken1ClaimableLPWithdrawal += balanceSurplus;
            balanceSurplus = 0;
            return;
        }

        // Wrap native token into token1 and re-deposit into the pool
        ISTEXAMM stexInterface = ISTEXAMM(stex);
        address token1Address = stexInterface.token1();
        IWETH9 token1 = IWETH9(token1Address);

        token1.deposit{value: balanceSurplus}();
        // Pool reserves are measured as balances, hence we can replenish it with token1
        // by transfering directly
        token1.safeTransfer(stexInterface.pool(), balanceSurplus);
    }

    /**
     * @notice Claims a LP withdrawal request which has already been fulfilled.
     * @dev Anyone can claim on behalf of its recipient.
     * @param _idLPQueue Id of LP's withdrawal request to claim.
     */
    function claim(uint256 _idLPQueue) external nonReentrant {
        LPWithdrawalRequest memory request = LPWithdrawals[_idLPQueue];

        if (request.amountToken1 == 0) {
            revert stHYPEWithdrawalModule__claim_alreadyClaimed();
        }

        // Check if there is enough ETH available to fulfill this request
        if (amountToken1ClaimableLPWithdrawal < request.amountToken1) {
            revert stHYPEWithdrawalModule__claim_insufficientAmountToClaim();
        }

        // Check if it is the right time to claim (according to queue priority)
        if (
            cumulativeAmountToken1ClaimableLPWithdrawal
                < request.cumulativeAmountToken1ClaimableLPWithdrawalCheckpoint + request.amountToken1
        ) {
            revert stHYPEWithdrawalModule__claim_cannotYetClaim();
        }

        amountToken1ClaimableLPWithdrawal -= request.amountToken1;

        emit LPWithdrawalRequestClaimed(_idLPQueue);

        delete LPWithdrawals[_idLPQueue];

        // Send equivalent amount of native token to recipient
        Address.sendValue(payable(request.recipient), request.amountToken1);
    }
}
