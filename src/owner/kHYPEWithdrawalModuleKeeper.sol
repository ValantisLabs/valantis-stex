// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {kHYPEWithdrawalModule} from "../withdrawal-modules/kHYPEWithdrawalModule.sol";

/**
 * @notice Keeper contract to automate routine function calls in `kHYPEWithdrawalModule`.
 * @dev This contract is supposed to route its calls via the `owner` of `kHYPEWithdrawalModule`.
 */
contract kHYPEWithdrawalModuleKeeper is Ownable {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error kHYPEWithdrawalModuleKeeper__ZeroAddress();
    error kHYPEWithdrawalModuleKeeper__call_onlyKeeper();
    error kHYPEWithdrawalModuleKeeper__call_callFailed();

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
            revert kHYPEWithdrawalModuleKeeper__ZeroAddress();
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
            revert kHYPEWithdrawalModuleKeeper__ZeroAddress();
        }
        isKeeper[_keeper] = false;
    }

    /**
     * @notice Allows an address with keeper role to execute an arbitrary external call.
     * @dev Only callable by an address with keeper role.
     * @param _withdrawalModuleManager Address of `kHYPEWithdrawalModule`'s owner,
     *        which should validate this call.
     * @param _payload Payload to execute.
     */
    function call(address _withdrawalModuleManager, bytes calldata _payload) external {
        if (!isKeeper[msg.sender]) {
            revert kHYPEWithdrawalModuleKeeper__call_onlyKeeper();
        }

        (bool success,) = _withdrawalModuleManager.call(_payload);
        if (!success) revert kHYPEWithdrawalModuleKeeper__call_callFailed();
    }

    /**
     * @notice Allows anyone to claim an array of LST protocol withdrawals and call Withdrawal Module's update function.
     * @param _burnIds Ids of LST protocol withdrawals in `_overseer` to claim.
     * @param _withdrawalModule Address of `kHYPEWithdrawalModule`.
     * @dev Returns a boolean array of same size as `_burnIds` to flag the ones which have been successfully claimed.
     */
    function redeemBurnsAndUpdate(uint256[] calldata _burnIds, address _withdrawalModule)
        external
        returns (bool[] memory)
    {
        bool[] memory burnIdsProcessed = new bool[](_burnIds.length);

        if (_burnIds.length > 0) {
            for (uint256 i; i < _burnIds.length; i++) {
                burnIdsProcessed[i] = kHYPEWithdrawalModule(payable(_withdrawalModule)).confirmWithdrawal(_burnIds[i]);
            }

            kHYPEWithdrawalModule(payable(_withdrawalModule)).update();
        }

        return burnIdsProcessed;
    }
}
