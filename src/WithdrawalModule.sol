// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {IOverseer} from "./interfaces/IOverseer.sol";
import {IstHYPE} from "./interfaces/IstHYPE.sol";
import {IWithdrawalModule} from "./interfaces/IWithdrawalModule.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {IHAMM} from "./interfaces/IHAMM.sol";
import {LPWithdrawalRequest} from "./structs/WithdrawalModuleStructs.sol";

contract WithdrawalModule is IWithdrawalModule, ReentrancyGuardTransient {
    using SafeCast for uint256;

    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error WithdrawalModule__ZeroAddress();
    error WithdrawalModule__OnlyInitializer();
    error WithdrawalModule__OnlyHAMM();
    error WithdrawalModule__claim_cannotYetClaim();
    error WithdrawalModule__claim_insufficientAmountToClaim();

    /**
     *
     *  IMMUTABLES
     *
     */
    address public immutable overseer;

    address public immutable initializer;

    /**
     *
     *  STORAGE
     *
     */
    address public hamm;

    /**
     * @notice Amount of `token0` pending unstaking in the `overseer` withdrawal queue.
     */
    uint256 public amountPendingUnstaking;

    /**
     * @notice Amount of native `token1` which is owed to HAMM LPs who have burnt their LP tokens.
     */
    uint256 public amountPendingLPWithdrawal;

    /**
     * @notice Amount of native `token1` which is ready for eligible HAMM LPs to claim.
     */
    uint256 public amountClaimableLPWithdrawal;

    /**
     * @notice Cumulative amount of native `token1` claimable by LP withdrawals.
     */
    uint256 public cumulativeAmountClaimableLPWithdrawal;

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
    constructor(address _overseer, address _initializer) {
        if (_overseer == address(0) || _initializer == address(0)) {
            revert WithdrawalModule__ZeroAddress();
        }

        overseer = _overseer;
        initializer = _initializer;
    }

    /**
     *
     *  MODIFIERS
     *
     */
    modifier onlyInitializer() {
        if (msg.sender != initializer) {
            revert WithdrawalModule__OnlyInitializer();
        }
        _;
    }

    modifier onlyHAMM() {
        if (msg.sender != hamm) {
            revert WithdrawalModule__OnlyHAMM();
        }
        _;
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */
    function setHAMM(address _hamm) external onlyInitializer {
        if (_hamm == address(0)) revert WithdrawalModule__ZeroAddress();

        hamm = _hamm;
    }

    /**
     * @dev This contract will receive token1 in native form,
     *      as pending unstaking requests are settled.
     */
    receive() external payable nonReentrant {}

    function burnAfterWithdraw(uint256 _amountToken0, address _recipient) external override onlyHAMM nonReentrant {
        amountPendingLPWithdrawal += _amountToken0;
        LPWithdrawals[idLPWithdrawal] = LPWithdrawalRequest({
            recipient: _recipient,
            amount: _amountToken0.toUint96(),
            cumulativeAmountClaimableLPWithdrawalCheckpoint: cumulativeAmountClaimableLPWithdrawal
        });
        idLPWithdrawal++;
    }

    function unstakeToken0Reserves() external override nonReentrant {
        IHAMM hammInterface = IHAMM(hamm);
        hammInterface.unstakeToken0Reserves();

        address token0 = hammInterface.token0();
        uint256 amountToken0 = IstHYPE(token0).balanceOf(address(this));

        amountPendingUnstaking += amountToken0;

        // Burn amountToken0 worth of token0 through withdrawal queue.
        // Once completed, an equivalent amount of native token1 should be transferred into this contract
        IOverseer(overseer).burn(address(this), amountToken0);
    }

    function update() external nonReentrant {
        uint256 balanceCache = address(this).balance;
        // Need to ensure that enough ETH is reserved for settled LP withdrawals
        uint256 amountClaimableLPWithdrawalCache = amountClaimableLPWithdrawal;
        if (balanceCache == 0 || balanceCache <= amountClaimableLPWithdrawalCache) {
            return;
        }

        balanceCache -= amountClaimableLPWithdrawalCache;

        // Reduce token0 amount which is pending unstaking
        uint256 amountPendingUnstakingCache = amountPendingUnstaking;
        amountPendingUnstaking =
            balanceCache > amountPendingUnstakingCache ? 0 : amountPendingUnstakingCache - balanceCache;

        // Prioritize LP withdrawal requests
        uint256 amountPendingLPWithdrawalCache = amountPendingLPWithdrawal;
        if (balanceCache > amountPendingLPWithdrawalCache) {
            balanceCache -= amountPendingLPWithdrawalCache;
            amountClaimableLPWithdrawal += amountPendingLPWithdrawalCache;
            cumulativeAmountClaimableLPWithdrawal += amountPendingLPWithdrawalCache;
            amountPendingLPWithdrawal = 0;
        } else {
            amountPendingLPWithdrawal -= balanceCache;
            amountClaimableLPWithdrawal += balanceCache;
            cumulativeAmountClaimableLPWithdrawal += balanceCache;
            balanceCache = 0;
            return;
        }

        // Wrap native token into token1 and re-deposit into the pool
        IHAMM hammInterface = IHAMM(hamm);
        address token1Address = hammInterface.token1();
        IWETH9 token1 = IWETH9(token1Address);

        token1.deposit{value: balanceCache}();
        token1.approve(hamm, balanceCache);

        hammInterface.replenishPool(balanceCache);
    }

    function claim(uint256 _idLPQueue) external nonReentrant {
        LPWithdrawalRequest memory request = LPWithdrawals[_idLPQueue];

        // Check if there is enough ETH available to fulfill this request
        if (request.amount < amountClaimableLPWithdrawal) {
            revert WithdrawalModule__claim_insufficientAmountToClaim();
        }

        // Check if it is the right time to claim (according to queue priority)
        if (
            cumulativeAmountClaimableLPWithdrawal
                < request.cumulativeAmountClaimableLPWithdrawalCheckpoint + request.amount
        ) {
            revert WithdrawalModule__claim_cannotYetClaim();
        }

        amountClaimableLPWithdrawal -= request.amount;

        delete LPWithdrawals[_idLPQueue];

        // Send equivalent amount of native token to recipient
        Address.sendValue(payable(request.recipient), request.amount);
    }
}
