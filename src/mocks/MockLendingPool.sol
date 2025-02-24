// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPool} from "../interfaces/aavev3/IPool.sol";

contract MockLendingPool is IPool {
    using SafeERC20 for ERC20;

    address public immutable underlyingAsset;

    address public immutable lendingPoolYieldToken;

    bool public isCompromised;

    mapping(address account => uint256) private _shares;

    uint256 private _totalSupply;

    constructor(address _underlyingAsset) {
        lendingPoolYieldToken = address(this);
        underlyingAsset = _underlyingAsset;
    }

    function balanceOf(address account) external view returns (uint256) {
        return
            _totalSupply == 0 ? 0 : (_shares[account] * ERC20(underlyingAsset).balanceOf(address(this))) / _totalSupply;
    }

    function setIsCompromised(bool value) public {
        isCompromised = value;
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 /*referralCode*/ ) external override {
        require(asset == underlyingAsset, "unexpected underlying asset");
        require(amount != 0, "amount cannot be zero");
        require(onBehalfOf != address(0), "onBehalfOf cannot be zero");

        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        uint256 underlyingBalance = ERC20(underlyingAsset).balanceOf(address(this));
        uint256 sharesToMint = _totalSupply == 0 ? amount : (amount * _totalSupply) / underlyingBalance;

        _shares[onBehalfOf] += sharesToMint;
        _totalSupply += sharesToMint;
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        require(asset == underlyingAsset, "unexpected underlying asset");
        require(to != address(0), "to cannot be zero");

        if (amount == 0) {
            return 0;
        }

        uint256 maxShares = _shares[msg.sender];
        uint256 underlyingBalance = ERC20(underlyingAsset).balanceOf(address(this));
        uint256 shares = (amount * _totalSupply) / underlyingBalance;

        require(shares <= maxShares, "excessive withdrawal amount");

        _shares[msg.sender] -= shares;
        _totalSupply -= shares;

        ERC20(asset).safeTransfer(to, isCompromised ? 0 : amount);

        return amount;
    }
}
