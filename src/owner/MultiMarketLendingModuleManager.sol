// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MultiMarketLendingModule} from "../lending-modules/MultiMarketLendingModule.sol";

contract MultiMarketLendingModuleManager is Ownable {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error MultiMarketLendingModuleManager__OnlyKeeper();
    error MultiMarketLendingModuleManager__ZeroAddress();
    error MultiMarketLendingModuleManager__call_callFailed();

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
            revert MultiMarketLendingModuleManager__ZeroAddress();
        }

        keeper = _keeper;
    }

    /**
     *
     *  MODIFIERS
     *
     */
    modifier onlyKeeper() {
        if (msg.sender != keeper) {
            revert MultiMarketLendingModuleManager__OnlyKeeper();
        }
        _;
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Accepts ownership of `_lendingModule`.
     * @dev Only callable by `owner`.
     */
    function acceptOwnership(address _lendingModule) external onlyOwner {
        MultiMarketLendingModule(_lendingModule).acceptOwnership();
    }

    /**
     * @notice Set `_keeper` as the keeper role.
     * @dev Only callable by `owner`.
     */
    function setKeeper(address _keeper) external onlyOwner {
        if (_keeper == address(0)) {
            revert MultiMarketLendingModuleManager__ZeroAddress();
        }

        keeper = _keeper;
    }

    /**
     * @notice Allows `owner` to execute an arbitrary external call.
     * @dev Only callable by `owner`.
     * @dev `owner` can call any function in `_lendingModule`, including keeper functions.
     * @param _lendingModule Address of `MultiMarketLendingModule`,
     *        which should have this contract as its `owner`.
     * @param _payload Payload to execute.
     */
    function call(address _lendingModule, bytes calldata _payload) external onlyOwner {
        (bool success,) = _lendingModule.call(_payload);
        if (!success) revert MultiMarketLendingModuleManager__call_callFailed();
    }

    /**
     * @notice Sets the deposit weights for each market in `_lendingModule`.
     * @dev Only callable by `keeper`.
     * @param _lendingModule Address of `MultiMarketLendingModule`.
     * @param _depositWeightBipsArray Array of deposit weights for each market.
     */
    function setDepositWeights(address _lendingModule, uint16[] memory _depositWeightBipsArray) external onlyKeeper {
        MultiMarketLendingModule(_lendingModule).setDepositWeights(_depositWeightBipsArray);
    }

    /**
     * @notice Sets the withdrawal weights for each market in `_lendingModule`.
     * @dev Only callable by `keeper`.
     * @param _lendingModule Address of `MultiMarketLendingModule`.
     * @param _withdrawWeightBipsArray Array of withdrawal weights for each market.
     */
    function setWithdrawWeights(address _lendingModule, uint16[] memory _withdrawWeightBipsArray) external onlyKeeper {
        MultiMarketLendingModule(_lendingModule).setWithdrawWeights(_withdrawWeightBipsArray);
    }

    /**
     * @notice Claims manager fee from `_lendingModule` and sends it to `_recipient`.
     * @dev Only callable by `keeper`.
     * @param _lendingModule Address of `MultiMarketLendingModule`.
     * @param _recipient Address to send the manager fee to.
     */
    function claimManagerFee(address _lendingModule, address _recipient) external onlyKeeper {
        MultiMarketLendingModule(_lendingModule).claimManagerFee(_recipient);
    }
}
