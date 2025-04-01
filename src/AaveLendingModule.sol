// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILendingModule} from "./interfaces/ILendingModule.sol";
import {IPool} from "./interfaces/aavev3/IPool.sol";

/**
 * @notice Wrapper contract that allows its owner to lend an underlying token on AAVE V3 pools.
 */
contract AaveLendingModule is ILendingModule, Ownable {
    using SafeERC20 for IERC20;

    /**
     *
     *  IMMUTABLES
     *
     */
    IPool public immutable pool;

    address public immutable yieldToken;

    address public immutable asset;

    uint16 public immutable referralCode;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _pool, address _yieldToken, address _asset, address _owner, uint16 _referralCode)
        Ownable(_owner)
    {
        pool = IPool(_pool);
        yieldToken = _yieldToken;
        asset = _asset;
        referralCode = _referralCode;
    }

    /**
     *
     *  VIEW FUNCTIONS
     *
     */

    /**
     * @notice Returns amount of asset token owned in the lending module.
     */
    function assetBalance() external view returns (uint256) {
        return IERC20(yieldToken).balanceOf(address(this));
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Deposits asset token into the lending pool.
     * @param _amount Amount of asset token to deposit.
     * @dev Only the owner can deposit asset token into the lending pool.
     */
    function deposit(uint256 _amount) external onlyOwner {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(asset).forceApprove(address(pool), _amount);
        IPool(pool).supply(asset, _amount, address(this), referralCode);
    }

    /**
     * @notice Withdraws asset token from the lending pool.
     * @param _amount Amount of asset token to withdraw.
     * @param _recipient Address to receive the withdrawn asset token.
     * @dev Only the owner can withdraw asset token from the lending pool.
     */
    function withdraw(uint256 _amount, address _recipient) external onlyOwner {
        pool.withdraw(asset, _amount, _recipient);
    }
}
