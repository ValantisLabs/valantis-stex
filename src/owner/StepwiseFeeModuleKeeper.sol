// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {StepwiseFeeModule} from "../swap-fee-modules/StepwiseFeeModule.sol";

/**
 * @notice Keeper contract to automate params setting in StepwiseFeeModule contract.
 * @dev The keeper role is assignable and revokable by an owner.
 */
contract StepwiseFeeModuleKeeper is Ownable {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error StepwiseFeeModuleKeeper__ZeroAddress();
    error StepwiseFeeModuleKeeper__setFeeParamsToken0_OnlyKeeper();

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
            revert StepwiseFeeModuleKeeper__ZeroAddress();
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
            revert StepwiseFeeModuleKeeper__ZeroAddress();
        }
        isKeeper[_keeper] = false;
    }

    /**
     * @notice Allows an address with keeper role to update token0 related parameters
     *         in `_swapFeeModule`.
     * @dev Only callable by an address with keeper role.
     * @param _swapFeeModule Address of StepwiseFeeModule contract to call.
     * @param _minThresholdToken1 New parameter value for StepwiseFeeModule
     * @param _maxThresholdToken1 New parameter value for StepwiseFeeModule.
     * @param _feeStepsInBips New parameter value for StepwiseFeeModule.
     */
    function setFeeParamsToken0(
        address _swapFeeModule,
        uint256 _minThresholdToken1,
        uint256 _maxThresholdToken1,
        uint32[] calldata _feeStepsInBips
    ) external {
        if (!isKeeper[msg.sender]) {
            revert StepwiseFeeModuleKeeper__setFeeParamsToken0_OnlyKeeper();
        }

        if (_swapFeeModule == address(0)) {
            revert StepwiseFeeModuleKeeper__ZeroAddress();
        }

        StepwiseFeeModule(_swapFeeModule).setFeeParamsToken0(_minThresholdToken1, _maxThresholdToken1, _feeStepsInBips);
    }
}
