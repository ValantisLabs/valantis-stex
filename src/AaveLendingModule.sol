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
     *  EVENTS
     *
     */
    event TokenSweepManagerUpdated(address tokenSweepManager);
    event Sweep(address indexed token, address indexed recipient, uint256 balance);

    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error AaveLendingModule__OnlyTokenSweepManager();
    error AaveLendingModule__ZeroAddress();
    error AaveLendingModule__sweep_assetCannotBeSweeped();
    error AaveLendingModule__sweep_yieldTokenCannotBeSweeped();

    /**
     *
     *  IMMUTABLES
     *
     */

    /**
     * @notice AAVE V3 Pool contract.
     */
    IPool public immutable pool;

    /**
     * @notice aToken address corresponding to `asset`.
     */
    address public immutable yieldToken;

    /**
     * @notice ERC-20 token to be supplied.
     */
    address public immutable asset;

    uint16 public immutable referralCode;

    /**
     * @notice Role which is able to call `sweep`.
     * @dev It can sweep any stuck token balances, except `yieldToken` and `asset`.
     */
    address public tokenSweepManager;

    /**
     *
     *  MODIFIERS
     *
     */
    modifier onlyTokenSweepManager() {
        if (msg.sender != tokenSweepManager) {
            revert AaveLendingModule__OnlyTokenSweepManager();
        }
        _;
    }

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(
        address _pool,
        address _yieldToken,
        address _asset,
        address _owner,
        address _tokenSweepManager,
        uint16 _referralCode
    ) Ownable(_owner) {
        pool = IPool(_pool);
        yieldToken = _yieldToken;
        asset = _asset;
        tokenSweepManager = _tokenSweepManager;
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
    function setTokenSweepManager(address _tokenSweepManager) external onlyTokenSweepManager {
        if (_tokenSweepManager == address(0)) {
            revert AaveLendingModule__ZeroAddress();
        }

        tokenSweepManager = _tokenSweepManager;

        emit TokenSweepManagerUpdated(_tokenSweepManager);
    }

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

    /**
     * @notice Sweep token balances which have been locked into this contract.
     * @dev Only callable by `tokenSweepManager`.
     * @param _token Token address to claim balances for.
     * @param _recipient Recipient of `_token` balance.
     */
    function sweep(address _token, address _recipient) external onlyTokenSweepManager {
        if (_token == address(0)) revert AaveLendingModule__ZeroAddress();
        if (_recipient == address(0)) revert AaveLendingModule__ZeroAddress();

        if (_token == asset) {
            revert AaveLendingModule__sweep_assetCannotBeSweeped();
        }
        if (_token == yieldToken) {
            revert AaveLendingModule__sweep_yieldTokenCannotBeSweeped();
        }

        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(_token).safeTransfer(_recipient, balance);

            emit Sweep(_token, _recipient, balance);
        }
    }
}
