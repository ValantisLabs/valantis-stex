// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockERC4626LendingPool {
    using SafeERC20 for ERC20Mock;

    address public immutable underlyingAsset;

    bool public isCompromised;
    bool public isPartialDeposit;
    bool public isExcessTransfer;

    address public partialDepositRecipient;

    mapping(address account => uint256) private _shares;

    uint256 private _totalSupply;

    uint256 private _totalAssets;

    constructor(address _underlyingAsset) {
        underlyingAsset = _underlyingAsset;
    }

    function totalAssets() external view returns (uint256) {
        return _totalAssets;
    }

    function asset() external view returns (address) {
        return underlyingAsset;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _shares[account];
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        uint256 balance = ERC20Mock(underlyingAsset).balanceOf(address(this));
        uint256 maxAssets = balance > _totalAssets ? balance : _totalAssets;

        return _totalSupply == 0 ? 0 : (shares * maxAssets) / _totalSupply;
    }

    function maxWithdraw(address account) external view returns (uint256) {
        return _totalSupply == 0
            ? 0
            : (_shares[account] * ERC20Mock(underlyingAsset).balanceOf(address(this))) / _totalSupply;
    }

    function setIsCompromised(bool value) public {
        isCompromised = value;
    }

    function setIsPartialDeposit(bool value) public {
        isPartialDeposit = value;
    }

    function setIsExcessTransfer(bool value) public {
        isExcessTransfer = value;
    }

    function setPartialDepositRecipient(address value) public {
        partialDepositRecipient = value;
    }

    function deposit(uint256 amount, address recipient) external returns (uint256 shares) {
        require(amount != 0, "amount cannot be zero");
        require(recipient != address(0), "recipient cannot be zero");

        uint256 amountDeposited = amount;

        ERC20Mock(underlyingAsset).safeTransferFrom(msg.sender, address(this), amountDeposited);

        if (isPartialDeposit) {
            amountDeposited = amount / 2;
            // Return the remaining amount to the sender
            ERC20Mock(underlyingAsset).safeTransfer(partialDepositRecipient, amount - amountDeposited);
        }

        uint256 underlyingBalance = ERC20Mock(underlyingAsset).balanceOf(address(this));
        shares = _totalSupply == 0 ? amountDeposited : (amountDeposited * _totalSupply) / underlyingBalance;

        _shares[recipient] += shares;
        _totalSupply += shares;
        _totalAssets += amountDeposited;
    }

    function withdraw(uint256 assets, address receiver, address /*owner*/ ) external returns (uint256 shares) {
        require(receiver != address(0), "receiver cannot be zero");

        if (assets == 0) {
            return 0;
        }

        uint256 maxShares = _shares[msg.sender];
        uint256 underlyingBalance = ERC20Mock(underlyingAsset).balanceOf(address(this));
        shares = (assets * _totalSupply) / underlyingBalance;

        require(shares <= maxShares, "excessive withdrawal amount");

        _shares[msg.sender] -= shares;
        _totalSupply -= shares;
        _totalAssets -= assets;

        uint256 amountToTransfer = isCompromised ? 0 : assets;
        if (isExcessTransfer) {
            ERC20Mock(underlyingAsset).mint(receiver, 10 ether);
        }

        ERC20Mock(underlyingAsset).safeTransfer(receiver, amountToTransfer);
    }

    function removeToken(uint256 amount, address recipient) external {
        ERC20Mock(underlyingAsset).safeTransfer(recipient, amount);
    }
}
