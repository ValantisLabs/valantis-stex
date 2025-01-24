// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IOverseer} from "./interfaces/IOverseer.sol";
import {IstHYPE} from "./interfaces/IstHYPE.sol";
import {IWithdrawalModule} from "./interfaces/IWithdrawalModule.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {IHAMM} from "./interfaces/IHAMM.sol";
import {LPWithdrawalRequest} from "./structs/WithdrawalModuleStructs.sol";

contract WithdrawalModule is
    IWithdrawalModule,
    ReentrancyGuardTransient,
    Ownable
{
    using SafeCast for uint256;
    using SafeERC20 for IWETH9;

    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error WithdrawalModule__ZeroAddress();
    error WithdrawalModule__OnlyInitializer();
    error WithdrawalModule__OnlyHAMM();
    error WithdrawalModule__claim_alreadyClaimed();
    error WithdrawalModule__claim_cannotYetClaim();
    error WithdrawalModule__claim_insufficientAmountToClaim();
    error WithdrawalModule__setHAMM_AlreadySet();

    /**
     *
     *  IMMUTABLES
     *
     */
    address public immutable overseer;

    /**
     *
     *  STORAGE
     *
     */
    address public hamm;

    /**
     * @notice Amount of `token0` pending unstaking in the `overseer` withdrawal queue.
     */
    uint256 private _amountToken0PendingUnstaking;

    /**
     * @notice Amount of native `token1` which is owed to HAMM LPs who have burnt their LP tokens.
     */
    uint256 public amountToken1PendingLPWithdrawal;

    /**
     * @notice Amount of native `token1` which is ready for eligible HAMM LPs to claim.
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
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _overseer, address _owner) Ownable(_owner) {
        if (_overseer == address(0) || _owner == address(0)) {
            revert WithdrawalModule__ZeroAddress();
        }

        overseer = _overseer;
    }

    /**
     *
     *  MODIFIERS
     *
     */

    modifier onlyHAMM() {
        if (msg.sender != hamm) {
            revert WithdrawalModule__OnlyHAMM();
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
    ) public view override returns (uint256) {
        address token0 = IHAMM(hamm).token0();
        return IstHYPE(token0).assetsToShares(_amountToken1);
    }

    function convertToToken1(
        uint256 _amountToken0
    ) public view override returns (uint256) {
        address token0 = IHAMM(hamm).token0();
        return IstHYPE(token0).sharesToAssets(_amountToken0);
    }

    function amountToken0PendingUnstaking()
        public
        view
        override
        returns (uint256)
    {
        uint256 balanceNative = address(this).balance;
        uint256 excessNative = balanceNative > amountToken1ClaimableLPWithdrawal
            ? balanceNative - amountToken1ClaimableLPWithdrawal
            : 0;
        uint256 excessToken0 = excessNative > 0
            ? convertToToken0(excessNative)
            : 0;

        uint256 amountToken0PendingUnstakingCache = _amountToken0PendingUnstaking;
        if (amountToken0PendingUnstakingCache > excessToken0) {
            return amountToken0PendingUnstakingCache - excessToken0;
        } else {
            return 0;
        }
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */
    function setHAMM(address _hamm) external onlyOwner {
        if (_hamm == address(0)) revert WithdrawalModule__ZeroAddress();
        // Can only be set once
        if (hamm != address(0)) revert WithdrawalModule__setHAMM_AlreadySet();

        hamm = _hamm;
    }

    /**
     * @dev This contract will receive token1 in native form,
     *      as pending unstaking requests are settled.
     */
    receive() external payable nonReentrant {}

    function burnToken0AfterWithdraw(
        uint256 _amountToken0,
        address _recipient
    ) external override onlyHAMM nonReentrant {
        // stHYPE's balances represent shares,
        // so we need to calculate the equivalent amount expected in token1 (equivalently, native token)
        uint256 amountToken1 = convertToToken1(_amountToken0);

        amountToken1PendingLPWithdrawal += amountToken1;

        LPWithdrawals[idLPWithdrawal] = LPWithdrawalRequest({
            recipient: _recipient,
            amountToken1: amountToken1.toUint96(),
            cumulativeAmountToken1ClaimableLPWithdrawalCheckpoint: cumulativeAmountToken1ClaimableLPWithdrawal
        });
        idLPWithdrawal++;
    }

    function unstakeToken0Reserves() external override nonReentrant onlyOwner {
        IHAMM hammInterface = IHAMM(hamm);
        hammInterface.unstakeToken0Reserves();

        address token0 = hammInterface.token0();
        uint256 amountToken0 = IstHYPE(token0).balanceOf(address(this));

        _amountToken0PendingUnstaking += amountToken0;

        // Burn amountToken0 worth of token0 through withdrawal queue.
        // Once completed, an equivalent amount of native token1 should be transferred into this contract
        // WARNING: token0 balances represent shares,
        // hence the equivalent amount of token1 to be received is not 1:1
        IOverseer(overseer).burn(address(this), amountToken0);
    }

    function update() external nonReentrant {
        uint256 balanceCache = address(this).balance;
        // Need to ensure that enough native token is reserved for settled LP withdrawals
        uint256 amountToken1ClaimableLPWithdrawalCache = amountToken1ClaimableLPWithdrawal;
        if (
            balanceCache == 0 ||
            balanceCache <= amountToken1ClaimableLPWithdrawalCache
        ) {
            return;
        }

        balanceCache -= amountToken1ClaimableLPWithdrawalCache;

        // Having a surplus balance of native token means that new unstaking requests have been processed
        uint256 excessToken0 = convertToToken0(balanceCache);
        if (_amountToken0PendingUnstaking > excessToken0) {
            _amountToken0PendingUnstaking -= excessToken0;
        } else {
            _amountToken0PendingUnstaking = 0;
        }

        // Prioritize LP withdrawal requests
        uint256 amountToken1PendingLPWithdrawalCache = amountToken1PendingLPWithdrawal;
        if (balanceCache > amountToken1PendingLPWithdrawalCache) {
            balanceCache -= amountToken1PendingLPWithdrawalCache;
            amountToken1ClaimableLPWithdrawal += amountToken1PendingLPWithdrawalCache;
            cumulativeAmountToken1ClaimableLPWithdrawal += amountToken1PendingLPWithdrawalCache;
            amountToken1PendingLPWithdrawal = 0;
        } else {
            amountToken1PendingLPWithdrawal -= balanceCache;
            amountToken1ClaimableLPWithdrawal += balanceCache;
            cumulativeAmountToken1ClaimableLPWithdrawal += balanceCache;
            balanceCache = 0;
            return;
        }

        // Wrap native token into token1 and re-deposit into the pool
        IHAMM hammInterface = IHAMM(hamm);
        address token1Address = hammInterface.token1();
        IWETH9 token1 = IWETH9(token1Address);

        token1.deposit{value: balanceCache}();
        // Pool reserves are measured as balances, hence we can replenish it with token1
        // by transferring directly
        token1.safeTransfer(hammInterface.pool(), balanceCache);
    }

    function claim(uint256 _idLPQueue) external nonReentrant {
        LPWithdrawalRequest memory request = LPWithdrawals[_idLPQueue];

        if (request.amountToken1 == 0) {
            revert WithdrawalModule__claim_alreadyClaimed();
        }

        // Check if there is enough ETH available to fulfill this request
        if (request.amountToken1 < amountToken1ClaimableLPWithdrawal) {
            revert WithdrawalModule__claim_insufficientAmountToClaim();
        }

        // Check if it is the right time to claim (according to queue priority)
        if (
            cumulativeAmountToken1ClaimableLPWithdrawal <
            request.cumulativeAmountToken1ClaimableLPWithdrawalCheckpoint +
                request.amountToken1
        ) {
            revert WithdrawalModule__claim_cannotYetClaim();
        }

        amountToken1ClaimableLPWithdrawal -= request.amountToken1;

        delete LPWithdrawals[_idLPQueue];

        // Send equivalent amount of native token to recipient
        Address.sendValue(payable(request.recipient), request.amountToken1);
    }
}
