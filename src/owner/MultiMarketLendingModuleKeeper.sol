// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice Keeper contract to automate routine function calls in `MultiMarketLendingModule`.
 * @dev This contract is supposed to route its calls via the `owner` of `MultiMarketLendingModule`.
 */
contract MultiMarketLendingModuleKeeper is Ownable {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error MultiMarketLendingModuleKeeper__ZeroAddress();
    error MultiMarketLendingModuleKeeper__call_onlyKeeper();
    error MultiMarketLendingModuleKeeper__call_callFailed();

    /**
     *
     *  STORAGE
     *
     */

    /**
     * @dev Tracks whitelisted addresses which have the keeper role.
     */
    mapping(address => bool) public isKeeper;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _owner) Ownable(_owner) {}

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Assigns keeper role to `_keeper`.
     * @dev Only callable by `owner`.
     * @param _keeper Address to grant the keeper role to.
     */
    function setKeeper(address _keeper) external onlyOwner {
        if (_keeper == address(0)) {
            revert MultiMarketLendingModuleKeeper__ZeroAddress();
        }
        isKeeper[_keeper] = true;
    }

    /**
     * @notice Revokes the keeper role from `_keeper`.
     * @dev Only callable by `owner`.
     * @param _keeper Address to revoke the keeper role from.
     */
    function removeKeeper(address _keeper) external onlyOwner {
        if (_keeper == address(0)) {
            revert MultiMarketLendingModuleKeeper__ZeroAddress();
        }
        isKeeper[_keeper] = false;
    }

    /**
     * @notice Allows an address with keeper role to execute an arbitrary external call.
     * @dev Only callable by an address with keeper role.
     * @param _lendingModuleManager Address of `MultiMarketLendingModule`'s owner,
     *        which should validate this call.
     * @param _payload Payload to execute.
     */
    function call(address _lendingModuleManager, bytes calldata _payload) external {
        if (!isKeeper[msg.sender]) {
            revert MultiMarketLendingModuleKeeper__call_onlyKeeper();
        }

        (bool success,) = _lendingModuleManager.call(_payload);
        if (!success) revert MultiMarketLendingModuleKeeper__call_callFailed();
    }
}
