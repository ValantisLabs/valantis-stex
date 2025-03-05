// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IstHYPE} from "../interfaces/IstHYPE.sol";

contract MockStHype is ERC20, IstHYPE {
    constructor() ERC20("Mock Staked HYPE", "MockstHYPE") {}

    receive() external payable {}

    function mint(address to) external payable returns (uint256 shares) {
        shares = totalSupply() == 0 ? msg.value : balanceToShares(msg.value);
        super._mint(to, shares);
    }

    function burn(address from, uint256 shares) external {
        super._burn(from, shares);
    }

    function balanceOf(address account) public view override(ERC20, IstHYPE) returns (uint256) {
        // When used by the test directly, return shares to maintain compatibility
        return super.balanceOf(account);
    }

    function sharesOf(address account) external view returns (uint256) {
        return super.balanceOf(account);
    }

    function sharesToBalance(uint256 shares) public view returns (uint256) {
        return totalSupply() == 0 ? 0 : (shares * address(this).balance) / totalSupply();
    }

    function balanceToShares(uint256 balance) public view returns (uint256) {
        return address(this).balance == 0 ? 0 : (balance * totalSupply()) / address(this).balance;
    }

    // Keep old methods for backward compatibility
    function sharesToAssets(uint256 shares) external view returns (uint256) {
        return sharesToBalance(shares);
    }

    function assetsToShares(uint256 assets) public view returns (uint256) {
        return balanceToShares(assets);
    }
}
