// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IWithdrawalModule} from "../interfaces/IWithdrawalModule.sol";

/**
 * @notice Owner contract for `stHYPEWithdrawalModule`.
 * @dev It separates the keeper role from more critical `owner` controlled functionality.
 *      Keeper role can automate non-timelocked functions in `stHYPEWithdrawalModule`.
 */
contract stHYPEWithdrawalModuleManager is Ownable {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error stHYPEWithdrawalModuleManager__OnlyKeeper();
    error stHYPEWithdrawalModuleManager__ZeroAddress();
    error stHYPEWithdrawalModuleManager__unstakeToken0Reserves_onlyKeeper();
    error stHYPEWithdrawalModuleManager__call_callFailed();

    /**
     *
     *  STORAGE
     *
     */

    /**
     * @dev Address of keeper role.
     */
    address public keeper;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _owner, address _keeper) Ownable(_owner) {
        if (_keeper == address(0)) {
            revert stHYPEWithdrawalModuleManager__ZeroAddress();
        }
        keeper = _keeper;
    }

    /**
     *
     *  ONLY KEEPER
     *
     */
    modifier onlyKeeper() {
        if (msg.sender != keeper) {
            revert stHYPEWithdrawalModuleManager__OnlyKeeper();
        }
        _;
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Set `_keeper` as the keeper role.
     * @dev Only callable by `owner`.
     */
    function setKeeper(address _keeper) external onlyOwner {
        if (_keeper == address(0)) {
            revert stHYPEWithdrawalModuleManager__ZeroAddress();
        }
        keeper = _keeper;
    }

    /**
     * @notice Allows `owner` to execute an arbitrary external call.
     * @dev Only callable by `owner`.
     * @dev `owner` can call any function in `_withdrawalModule`, including keeper functions.
     * @param _withdrawalModule Address of `stHYPEWithdrawalModule`,
     *        which should have this contract as its `owner`.
     * @param _payload Payload to execute.
     */
    function call(address _withdrawalModule, bytes calldata _payload) external onlyOwner {
        (bool success,) = _withdrawalModule.call(_payload);
        if (!success) revert stHYPEWithdrawalModuleManager__call_callFailed();
    }

    /**
     * @notice Unstake `amount` of token0 reserves from pool via `_withdrawalModule`.
     * @dev Only callable by keeper role.
     * @param _withdrawalModule Address of `stHYPEWithdrawalModule`.
     * @param _amount Amount of token0 reserves to withdraw from STEX pool.
     */
    function unstakeToken0Reserves(address _withdrawalModule, uint256 _amount) external onlyKeeper {
        IWithdrawalModule(_withdrawalModule).unstakeToken0Reserves(_amount);
    }

    /**
     * @notice Withdraw `_amountToken1` of token1 reserves from pool via `_withdrawalModule`,
     *         and supply to its respective lending pool integration.
     * @dev Only callable by keeper role.
     * @param _withdrawalModule Address of `stHYPEWithdrawalModule`.
     * @param _amountToken1 Amount of token1 reserves to withdraw from STEX pool.
     */
    function supplyToken1ToLendingPool(address _withdrawalModule, uint256 _amountToken1) external onlyKeeper {
        IWithdrawalModule(_withdrawalModule).supplyToken1ToLendingPool(_amountToken1);
    }

    /**
     * @notice Withdraw `_amountToken1` of token1 from lending pool integration,
     *         and transfer it back to the respective STEX pool.
     * @dev Only callable by keeper role.
     * @param _withdrawalModule Address of `stHYPEWithdrawalModule`.
     * @param _amountToken1 Amount of token1 reserves to withdraw from lending pool.
     */
    function withdrawToken1FromLendingPool(address _withdrawalModule, uint256 _amountToken1) external onlyKeeper {
        IWithdrawalModule(_withdrawalModule)
            .withdrawToken1FromLendingPool(
                _amountToken1,
                address(0) // _recipient is unused, since it must the STEX pool
            );
    }
}
