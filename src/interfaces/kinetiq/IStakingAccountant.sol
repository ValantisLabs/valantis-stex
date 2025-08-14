// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStakingAccountant {
    // View functions
    function totalStaked() external view returns (uint256);
    function totalClaimed() external view returns (uint256);
    function totalRewards() external view returns (uint256);
    function totalSlashing() external view returns (uint256);

    // Exchange ratio functions
    function kHYPEToHYPE(uint256 kHYPEAmount) external view returns (uint256);
    function HYPEToKHYPE(uint256 HYPEAmount) external view returns (uint256);

    // State changing functions
    function recordStake(uint256 amount) external;
    function recordClaim(uint256 amount) external;
}
