// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IstHYPE} from "../interfaces/IstHYPE.sol";

/**
 * @notice Mock contract for stHYPE.
 * @dev stHYPE is rebase.
 */
contract MockStHype is ERC20, IstHYPE {
    constructor() ERC20("Mock Staked HYPE", "MockstHYPE") {}

    receive() external payable {}

    function mint(address to) external payable returns (uint256 shares) {
        shares = balanceToShares(msg.value);
        super._mint(to, shares);
    }

    function burn(address from, uint256 shares) external {
        super._burn(from, shares);
    }

    function approve(address spender, uint256 value) public override(ERC20) returns (bool) {
        uint256 shares = balanceToShares(value);

        address owner = msg.sender;

        _approve(owner, spender, shares);

        return true;
    }

    function transfer(address to, uint256 value) public override(ERC20) returns (bool) {
        uint256 shares = balanceToShares(value);

        _transfer(msg.sender, to, shares);

        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override(ERC20) returns (bool) {
        uint256 shares = balanceToShares(value);

        address spender = msg.sender;

        _spendAllowance(from, spender, shares);
        _transfer(from, to, shares);

        return true;
    }

    function balanceOf(address account) public view override(ERC20, IstHYPE) returns (uint256) {
        uint256 shares = super.balanceOf(account);

        return sharesToBalance(shares);
    }

    function sharesOf(address account) external view returns (uint256) {
        return super.balanceOf(account);
    }

    function sharesToBalance(uint256 shares) public view returns (uint256) {
        return totalSupply() == 0 ? shares : (shares * address(this).balance) / totalSupply();
    }

    function balanceToShares(uint256 balance) public view returns (uint256) {
        return totalSupply() == 0 ? balance : (balance * totalSupply()) / address(this).balance;
    }
}
