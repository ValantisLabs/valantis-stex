// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IOverseer} from "../interfaces/IOverseer.sol";
import {IWithdrawalModule} from "../interfaces/IWithdrawalModule.sol";

contract WithdrawalModuleKeeper is Ownable {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error WithdrawalModuleKeeper__ZeroAddress();
    error WithdrawalModuleKeeper__unstakeToken0Reserves_onlyKeeper();

    /**
     *
     *  STORAGE
     *
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
    function getOverseerBurnIds(address _overseer, address _account) external view returns (uint256[] memory) {
        return IOverseer(_overseer).getBurnIds(_account);
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */
    function setKeeper(address _keeper) external onlyOwner {
        if (_keeper == address(0)) revert WithdrawalModuleKeeper__ZeroAddress();
        isKeeper[_keeper] = true;
    }

    function removeKeeper(address _keeper) external onlyOwner {
        if (_keeper == address(0)) revert WithdrawalModuleKeeper__ZeroAddress();
        isKeeper[_keeper] = false;
    }

    function unstakeToken0Reserves(address _withdrawalModuleManager, uint256 amount) external {
        if (!isKeeper[msg.sender]) {
            revert WithdrawalModuleKeeper__unstakeToken0Reserves_onlyKeeper();
        }

        // Manager contract of the Withdrawal Module, which has the same interface function to be called
        IWithdrawalModule(_withdrawalModuleManager).unstakeToken0Reserves(amount);
    }

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
