// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IStakingAccountant} from "../../interfaces/kinetiq/IStakingAccountant.sol";

/**
 * @notice Mock contract for Kinetiq Protocol's Staking Accountant.
 */
contract MockStakingAccountant is IStakingAccountant {
    address public immutable kHYPE;

    uint256 public totalSlashing;

    uint256 public totalRewards;

    uint256 public totalStaked;

    uint256 public totalClaimed;

    constructor(address _kHYPE) {
        kHYPE = _kHYPE;
    }

    function kHYPEToHYPE(uint256 kHYPEAmount) public view override returns (uint256) {
        return Math.mulDiv(kHYPEAmount, _getExchangeRatio(), 1e18);
    }

    function HYPEToKHYPE(uint256 HYPEAmount) public view override returns (uint256) {
        uint256 exchangeRatio = _getExchangeRatio();
        require(exchangeRatio > 0, "Invalid exchange ratio");
        return Math.mulDiv(HYPEAmount, 1e18, exchangeRatio);
    }

    function setTotalSlashing(uint256 _totalSlashing) external {
        totalSlashing = _totalSlashing;
    }

    function setTotalRewards(uint256 _totalRewards) external {
        totalRewards = _totalRewards;
    }

    function recordStake(uint256 amount) external override {
        totalStaked += amount;
    }

    function recordClaim(uint256 amount) external override {
        totalClaimed += amount;
    }

    function _getExchangeRatio() private view returns (uint256) {
        // Calculate total kHYPE supply across all unique tokens
        uint256 totalKHYPESupply = ERC20(kHYPE).totalSupply();

        // Return 1:1 ratio when no kHYPE has been minted yet
        if (totalKHYPESupply == 0) {
            return 1e18; // 1:1 ratio with 18 decimals precision
        }

        // Calculate total HYPE
        uint256 totalHYPE = totalStaked + totalRewards - totalClaimed - totalSlashing;

        // Calculate ratio with 18 decimals precision
        return Math.mulDiv(totalHYPE, 1e18, totalKHYPESupply);
    }
}
