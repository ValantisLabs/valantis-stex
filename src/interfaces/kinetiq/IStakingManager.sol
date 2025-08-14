// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStakingManager {
    /* ========== STRUCTS ========== */

    struct WithdrawalRequest {
        uint256 hypeAmount; // Amount in HYPE to withdraw
        uint256 kHYPEAmount; // Amount in kHYPE to burn (excluding fee)
        uint256 kHYPEFee; // Fee amount in kHYPE tokens
        uint256 timestamp; // Request timestamp
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Gets withdrawal request details for a user
    function withdrawalRequests(address user, uint256 id) external view returns (WithdrawalRequest memory);

    /// @notice Gets the next withdrawal ID for a user
    function nextWithdrawalId(address user) external view returns (uint256);

    /// @notice Gets the current unstake fee rate
    function unstakeFeeRate() external view returns (uint256);

    /// @notice Gets the withdrawal delay period
    function withdrawalDelay() external view returns (uint256);

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Stakes HYPE tokens
    function stake() external payable;

    /// @notice Queues a withdrawal request
    function queueWithdrawal(uint256 amount) external;

    /// @notice Confirms a withdrawal request
    function confirmWithdrawal(uint256 withdrawalId) external;
}
