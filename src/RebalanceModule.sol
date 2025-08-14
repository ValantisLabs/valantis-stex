// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IRebalanceModule} from "./interfaces/IRebalanceModule.sol";

/**
 * @title RebalanceModule
 * @notice This contract is used to rebalance the STEX AMM pool by swapping token0 for token1.
 * @dev Only callable by the withdrawal module.
 */
contract RebalanceModule is IRebalanceModule, Ownable {
    using SafeERC20 for IERC20;

    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error RebalanceModule__ZeroAddress();
    error RebalanceModule__onlyWithdrawalModule();
    error RebalanceModule__rebalance_InsufficientToken1Received();
    error RebalanceModule__rebalance_TargetCallFailed();
    error RebalanceModule__rebalance_InvalidAmountToken1Min();
    error RebalanceModule__rebalance_InvalidAmountToken0();
    error RebalanceModule__rebalance_InsufficientToken0Received();
    error RebalanceModule__rebalance_InvalidPayloadArrayLength();

    /**
     *
     *  EVENTS
     *
     */
    event Sweep(address indexed token, address indexed recipient, uint256 amount);

    /**
     *
     *  IMMUTABLES
     *
     */
    address public immutable withdrawalModule;
    address public immutable pool;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _withdrawalModule, address _pool, address _owner) Ownable(_owner) {
        if (_withdrawalModule == address(0) || _pool == address(0)) {
            revert RebalanceModule__ZeroAddress();
        }

        withdrawalModule = _withdrawalModule;
        pool = _pool;
    }

    /**
     *
     *  MODIFIERS
     *
     */
    modifier onlyWithdrawalModule() {
        if (msg.sender != withdrawalModule) {
            revert RebalanceModule__onlyWithdrawalModule();
        }
        _;
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Sweep token balances which have been locked into this contract.
     * @dev Only callable by `owner`.
     * @param _token Token address to claim balances for.
     * @param _recipient Recipient of `_token` balance.
     */
    function sweep(address _token, address _recipient) external onlyOwner {
        if (_token == address(0)) revert RebalanceModule__ZeroAddress();
        if (_recipient == address(0)) {
            revert RebalanceModule__ZeroAddress();
        }

        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(_token).safeTransfer(_recipient, balance);

            emit Sweep(_token, _recipient, balance);
        }
    }

    /**
     * @notice Rebalance the STEX AMM pool by swapping token0 for token1.
     * @dev Only callable by the withdrawal module.
     * @param _amountToken1Min Minimum amount of token1 to receive.
     * @param _payload Payload containing all required data for rebalancing.
     */
    function rebalance(uint256 _amountToken1Min, bytes memory _payload)
        external
        override
        onlyWithdrawalModule
        returns (bytes4)
    {
        (
            address token0,
            address token1,
            uint256[] memory amountToken0Array,
            address[] memory targetAddresses,
            bytes[] memory payloads
        ) = abi.decode(_payload, (address, address, uint256[], address[], bytes[]));

        _validateInputs(_amountToken1Min, token0, token1, amountToken0Array, targetAddresses, payloads);

        uint256 amountToken1PreBalance = IERC20(token1).balanceOf(address(this));

        for (uint256 i = 0; i < amountToken0Array.length; i++) {
            // Approve the target contract to spend the token0 amount
            IERC20(token0).forceApprove(targetAddresses[i], amountToken0Array[i]);

            // Call the target contract to swap token0 for token1
            (bool success,) = targetAddresses[i].call(payloads[i]);
            if (!success) {
                revert RebalanceModule__rebalance_TargetCallFailed();
            }
        }

        // Ensure that enough token1 amount has been received
        uint256 amountToken1 = IERC20(token1).balanceOf(address(this)) - amountToken1PreBalance;
        if (amountToken1 < _amountToken1Min) {
            revert RebalanceModule__rebalance_InsufficientToken1Received();
        }

        // Return token1 amount received to withdrawal module
        IERC20(token1).safeTransfer(withdrawalModule, amountToken1);

        // Return any remaining token0 to the pool
        uint256 balanceToken0 = IERC20(token0).balanceOf(address(this));
        if (balanceToken0 != 0) {
            IERC20(token0).safeTransfer(pool, balanceToken0);
        }

        return IRebalanceModule.rebalance.selector;
    }

    function _validateInputs(
        uint256 _amountToken1Min,
        address token0,
        address token1,
        uint256[] memory amountToken0Array,
        address[] memory targetAddresses,
        bytes[] memory payloads
    ) internal view {
        // Zero value checks
        if (_amountToken1Min == 0) {
            revert RebalanceModule__rebalance_InvalidAmountToken1Min();
        }

        if (token0 == address(0) || token1 == address(0)) {
            revert RebalanceModule__ZeroAddress();
        }

        for (uint256 i; i < targetAddresses.length; i++) {
            if (targetAddresses[i] == address(0)) {
                revert RebalanceModule__ZeroAddress();
            }
        }

        // Array length checks
        if (amountToken0Array.length != targetAddresses.length || amountToken0Array.length != payloads.length) {
            revert RebalanceModule__rebalance_InvalidPayloadArrayLength();
        }

        // token0 balance and amounts consistency checks
        uint256 amountToken0 = IERC20(token0).balanceOf(address(this));
        uint256 amountToken0Total;
        for (uint256 i = 0; i < amountToken0Array.length; i++) {
            uint256 amount = amountToken0Array[i];
            if (amount == 0) {
                revert RebalanceModule__rebalance_InvalidAmountToken0();
            }

            amountToken0Total += amount;
        }
        if (amountToken0Total != amountToken0) {
            revert RebalanceModule__rebalance_InsufficientToken0Received();
        }
    }
}
