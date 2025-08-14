// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IStakingAccountant} from "../../interfaces/kinetiq/IStakingAccountant.sol";
import {IStakingManager} from "../../interfaces/kinetiq/IStakingManager.sol";

/**
 * @notice Mock contract for Kinetiq Protocol's Staking Manager.
 */
contract MockStakingManager is IStakingManager {
    address public constant TREASURY = address(2);

    address public immutable kHYPE;

    IStakingAccountant public immutable stakingAccountant;

    uint256 public totalClaimed;

    uint256 public totalStaked;

    uint256 public totalQueuedWithdrawals; // Total amount of all pending withdrawal requests

    uint256 public unstakeFeeRate; // Fee rate in basis points (10 = 0.1%)

    // User tracking
    mapping(address => uint256) public nextWithdrawalId;

    uint256 private _cancelledWithdrawalAmount;

    mapping(address => mapping(uint256 => WithdrawalRequest)) private _withdrawalRequests;

    constructor(address _stakingAccountant, address _kHYPE) {
        stakingAccountant = IStakingAccountant(_stakingAccountant);
        kHYPE = _kHYPE;
    }

    function withdrawalDelay() external pure override returns (uint256) {
        return 7 days;
    }

    function withdrawalRequests(address user, uint256 id) external view override returns (WithdrawalRequest memory) {
        return _withdrawalRequests[user][id];
    }

    function setUnstakeFeeRate(uint256 newRate) external {
        require(newRate <= 1_000, "Fee rate too high"); // Max 10%
        unstakeFeeRate = newRate;
    }

    function stake() external payable override {
        require(msg.value > 0, "invalid amount staked");

        totalStaked += msg.value;

        // Convert HYPE to kHYPE amount using exchange ratio
        uint256 kHYPEAmount = stakingAccountant.HYPEToKHYPE(msg.value);

        // Mint kHYPE tokens based on the conversion
        ERC20Mock(kHYPE).mint(msg.sender, kHYPEAmount);

        stakingAccountant.recordStake(msg.value);
    }

    function queueWithdrawal(uint256 kHYPEAmount) external override {
        require(kHYPEAmount > 0, "Invalid amount");
        require(ERC20Mock(kHYPE).balanceOf(msg.sender) >= kHYPEAmount, "Insufficient kHYPE balance");

        uint256 withdrawalId = nextWithdrawalId[msg.sender];

        uint256 kHYPEFee = Math.mulDiv(kHYPEAmount, unstakeFeeRate, 10_000);
        uint256 postFeeKHYPE = kHYPEAmount - kHYPEFee;

        uint256 hypeAmount = stakingAccountant.kHYPEToHYPE(postFeeKHYPE);

        // Lock kHYPE tokens
        ERC20Mock(kHYPE).transferFrom(msg.sender, address(this), kHYPEAmount);

        // Create withdrawal request
        _withdrawalRequests[msg.sender][withdrawalId] = WithdrawalRequest({
            hypeAmount: hypeAmount,
            kHYPEAmount: postFeeKHYPE,
            kHYPEFee: kHYPEFee,
            timestamp: block.timestamp
        });

        nextWithdrawalId[msg.sender]++;
        totalQueuedWithdrawals += hypeAmount;
    }

    function confirmWithdrawal(uint256 withdrawalId) external override {
        uint256 amount = _processConfirmation(msg.sender, withdrawalId);
        require(amount > 0, "No valid withdrawal request");
        require(address(this).balance >= amount, "Insufficient contract balance");

        stakingAccountant.recordClaim(amount);

        // Process withdrawal using call instead of transfer
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
    }

    function cancelWithdrawal(address user, uint256 withdrawalId) external {
        WithdrawalRequest storage request = _withdrawalRequests[user][withdrawalId];
        require(request.hypeAmount > 0, "No such withdrawal request");

        uint256 hypeAmount = request.hypeAmount;
        uint256 kHYPEAmount = request.kHYPEAmount;
        uint256 kHYPEFee = request.kHYPEFee;

        // Check kHYPE balances
        require(ERC20Mock(kHYPE).balanceOf(address(this)) >= kHYPEAmount + kHYPEFee, "Insufficient kHYPE balance");

        // Clear the withdrawal request
        delete _withdrawalRequests[user][withdrawalId];
        totalQueuedWithdrawals -= hypeAmount;

        // Return kHYPE tokens to user (including fees)
        ERC20Mock(kHYPE).transfer(user, kHYPEAmount + kHYPEFee);

        // Track cancelled amount for future redelegation
        _cancelledWithdrawalAmount += hypeAmount;
    }

    function _processConfirmation(address user, uint256 withdrawalId) internal returns (uint256) {
        WithdrawalRequest memory request = _withdrawalRequests[user][withdrawalId];

        // Skip if request doesn't exist or delay period not met
        if (request.hypeAmount == 0 || block.timestamp < request.timestamp + 7 days) {
            return 0;
        }

        uint256 hypeAmount = request.hypeAmount;
        uint256 kHYPEAmount = request.kHYPEAmount;
        uint256 kHYPEFee = request.kHYPEFee;

        // Check kHYPE balances
        require(ERC20Mock(kHYPE).balanceOf(address(this)) >= kHYPEAmount + kHYPEFee, "Insufficient kHYPE balance");

        // Update state
        totalQueuedWithdrawals -= hypeAmount;
        totalClaimed += hypeAmount;
        delete _withdrawalRequests[user][withdrawalId];

        // Burn kHYPE tokens (excluding fee)
        ERC20Mock(kHYPE).burn(address(this), kHYPEAmount);

        // Transfer fee to treasury
        ERC20Mock(kHYPE).transfer(TREASURY, kHYPEFee);

        return hypeAmount;
    }
}
