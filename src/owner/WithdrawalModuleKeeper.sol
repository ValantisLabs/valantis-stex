// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IOverseer} from "../interfaces/IOverseer.sol";
import {IWithdrawalModule} from "../interfaces/IWithdrawalModule.sol";

/**
 * @notice Keeper contract to automate routine function calls in Withdrawal Module.
 * @dev This contract is supposed to route its calls via the `owner` of Withdrawal Module.
 */
contract WithdrawalModuleKeeper is Ownable {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error WithdrawalModuleKeeper__ZeroAddress();
    error WithdrawalModuleKeeper__call_onlyKeeper();
    error WithdrawalModuleKeeper__call_callFailed();

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
     *  VIEW FUNCTIONS
     *
     */

    /**
     * @notice Returns all pending burn ids in `_overseer` contract for `_account`.
     * @param _overseer Address of LST protocol's withdrawal queue entrypoint.
     * @param _account Address to query pending burn ids for.
     */
    function getOverseerBurnIds(address _overseer, address _account) external view returns (uint256[] memory) {
        return IOverseer(_overseer).getBurnIds(_account);
    }

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
        if (_keeper == address(0)) revert WithdrawalModuleKeeper__ZeroAddress();
        isKeeper[_keeper] = true;
    }

    /**
     * @notice Revokes the keeper role from `_keeper`.
     * @dev Only callable by `owner`.
     * @param _keeper Address to revoke the keeper role from.
     */
    function removeKeeper(address _keeper) external onlyOwner {
        if (_keeper == address(0)) revert WithdrawalModuleKeeper__ZeroAddress();
        isKeeper[_keeper] = false;
    }

    /**
     * @notice Allows an address with keeper role to execute an arbitrary external call.
     * @dev Only callable by an address with keeper role.
     * @param _withdrawalModuleManager Address of Withdrawal Module's owner, which should validate this call.
     * @param _payload Payload to execute.
     */
    function call(address _withdrawalModuleManager, bytes calldata _payload) external {
        if (!isKeeper[msg.sender]) {
            revert WithdrawalModuleKeeper__call_onlyKeeper();
        }

        (bool success,) = _withdrawalModuleManager.call(_payload);
        if (!success) revert WithdrawalModuleKeeper__call_callFailed();
    }

    /**
     * @notice Allows anyone to claim an array of LST protocol withdrawals and call Withdrawal Module's update function.
     * @param _burnIds Ids of LST protocol withdrawals in `_overseer` to claim.
     * @param _overseer Address of LST protocol's withdrawal queue entrypoint.
     * @param _withdrawalModule Address of STEX Withdrawal Module.
     * @dev Returns a boolean array of same size as `_burnIds` to flag the ones which have been successfully claimed.
     */
    function redeemBurnsAndUpdate(uint256[] calldata _burnIds, address _overseer, address _withdrawalModule)
        external
        returns (bool[] memory)
    {
        bool[] memory burnIdsProcessed = new bool[](_burnIds.length);

        if (_burnIds.length > 0) {
            for (uint256 i; i < _burnIds.length; i++) {
                bool isRedeemable = IOverseer(_overseer).redeemable(_burnIds[i]);
                if (isRedeemable) {
                    IOverseer(_overseer).redeem(_burnIds[i]);
                    burnIdsProcessed[i] = true;
                }
            }

            IWithdrawalModule(_withdrawalModule).update();
        }

        return burnIdsProcessed;
    }
}
