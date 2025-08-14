// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {ILendingModule} from "../interfaces/ILendingModule.sol";

/**
 * @notice Wrapper contract that allows its owner to lend an underlying token on ERC4626 vaults.
 */
contract ERC4626LendingModule is ILendingModule, Ownable {
    using SafeERC20 for IERC20;

    /**
     *
     *  EVENTS
     *
     */
    event Sweep(address indexed token, address indexed recipient, uint256 balance);
    event TokenSweepManagerUpdated(address tokenSweepManager);

    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error ERC4626LendingModule__OnlyTokenSweepManager();
    error ERC4626LendingModule__ZeroAddress();
    error ERC4626LendingModule__sweep_VaultTokenCannotBeSweeped();

    /**
     *
     *  IMMUTABLES
     *
     */

    /**
     * @notice ERC-20 token to be supplied.
     */
    address public immutable asset;

    /**
     * @notice ERC4626 compatible lending market vault.
     */
    IERC4626 public immutable vault;

    /**
     *
     *  STORAGE
     *
     */

    /**
     * @notice Role which is able to call `sweep`.
     * @dev It can sweep any stuck token balances, except `vault`.
     */
    address public tokenSweepManager;

    /**
     *
     *  MODIFIERS
     *
     */
    modifier onlyTokenSweepManager() {
        if (msg.sender != tokenSweepManager) {
            revert ERC4626LendingModule__OnlyTokenSweepManager();
        }
        _;
    }

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _vault, address _owner, address _tokenSweepManager) Ownable(_owner) {
        if (_vault == address(0) || _tokenSweepManager == address(0)) {
            revert ERC4626LendingModule__ZeroAddress();
        }

        vault = IERC4626(_vault);
        asset = vault.asset();
        tokenSweepManager = _tokenSweepManager;
    }

    /**
     *
     *  VIEW FUNCTIONS
     *
     */

    /**
     * @notice Returns amount of asset token owned by this contract's position in the vault.
     * @dev WARNING: This must NOT decrease as utilization/borrowing increases.
     *      This represents the total amount of asset token, plus any accrued interest,
     *      that is owed to this contract,
     *      even when the vault has temporarily insufficient liquidity to fulfill the withdrawal.
     */
    function assetBalance() external view returns (uint256) {
        uint256 shares = vault.balanceOf(address(this));
        return vault.convertToAssets(shares);
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Sets the address of the token sweep manager.
     * @param _tokenSweepManager Address of the token sweep manager.
     * @dev Only callable by the current `tokenSweepManager`.
     */
    function setTokenSweepManager(address _tokenSweepManager) external onlyTokenSweepManager {
        if (_tokenSweepManager == address(0)) {
            revert ERC4626LendingModule__ZeroAddress();
        }

        tokenSweepManager = _tokenSweepManager;

        emit TokenSweepManagerUpdated(_tokenSweepManager);
    }

    /**
     * @notice Deposits asset token into the lending vault.
     * @param _amount Amount of asset token to deposit.
     * @dev Only the owner can deposit asset token into the lending vault.
     */
    function deposit(uint256 _amount) external onlyOwner {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(asset).forceApprove(address(vault), _amount);
        // WARNING: Partial deposits are not allowed
        vault.deposit(_amount, address(this));
    }

    /**
     * @notice Withdraws asset token from the lending vault.
     * @param _amount Amount of asset token to withdraw.
     * @param _recipient Address to receive the withdrawn asset vault.
     * @dev Only the owner can withdraw asset token from the lending vault.
     */
    function withdraw(uint256 _amount, address _recipient) external onlyOwner {
        vault.withdraw(_amount, _recipient, address(this));
    }

    /**
     * @notice Sweep token balances which have been locked into this contract.
     * @dev Only callable by `tokenSweepManager`.
     * @param _token Token address to claim balances for.
     * @param _recipient Recipient of `_token` balance.
     */
    function sweep(address _token, address _recipient) external onlyTokenSweepManager {
        if (_token == address(0)) revert ERC4626LendingModule__ZeroAddress();
        if (_recipient == address(0)) {
            revert ERC4626LendingModule__ZeroAddress();
        }

        if (_token == address(vault)) {
            revert ERC4626LendingModule__sweep_VaultTokenCannotBeSweeped();
        }

        IERC20 token = IERC20(_token);

        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) {
            token.safeTransfer(_recipient, balance);

            emit Sweep(_token, _recipient, balance);
        }
    }
}
