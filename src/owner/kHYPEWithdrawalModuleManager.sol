// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IWithdrawalModule} from "../interfaces/IWithdrawalModule.sol";
import {kHYPEWithdrawalModule} from "../withdrawal-modules/kHYPEWithdrawalModule.sol";

/**
 * @notice Owner contract for `kHYPEWithdrawalModule`.
 * @dev It separates the keeper role from more critical `owner` controlled functionality.
 *      Keeper role can automate non-timelocked functions in `kHYPEWithdrawalModule`.
 */
contract kHYPEWithdrawalModuleManager is Ownable {
    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error kHYPEWithdrawalModuleManager__OnlyKeeper();
    error kHYPEWithdrawalModuleManager__ZeroAddress();
    error kHYPEWithdrawalModuleManager__unstakeToken0Reserves_onlyKeeper();
    error kHYPEWithdrawalModuleManager__call_callFailed();

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
            revert kHYPEWithdrawalModuleManager__ZeroAddress();
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
            revert kHYPEWithdrawalModuleManager__OnlyKeeper();
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
            revert kHYPEWithdrawalModuleManager__ZeroAddress();
        }
        keeper = _keeper;
    }

    /**
     * @notice Allows `owner` to execute an arbitrary external call.
     * @dev Only callable by `owner`.
     * @dev `owner` can call any function in `_withdrawalModule`, including keeper functions.
     * @param _withdrawalModule Address of `kHYPEWithdrawalModule`,
     *        which should have this contract as its `owner`.
     * @param _payload Payload to execute.
     */
    function call(address _withdrawalModule, bytes calldata _payload) external onlyOwner {
        (bool success,) = _withdrawalModule.call(_payload);
        if (!success) revert kHYPEWithdrawalModuleManager__call_callFailed();
    }

    /**
     * @notice Withdraws a portion of pool's token1 reserves,
     *         and stakes into `stakingManager` for an equivalent amount of `token0`.
     * @dev Only callable by keeper role.
     * @param _withdrawalModule Address of `kHYPEWithdrawalModule`.
     * @param _amountToken1 Amount of pool's token1 reserves to stake into token0.
     */
    function stakeToken1(address _withdrawalModule, uint256 _amountToken1) external onlyKeeper {
        kHYPEWithdrawalModule(payable(_withdrawalModule)).stakeToken1(_amountToken1);
    }

    /**
     * @notice Unstake `amount` of token0 reserves from pool via `_withdrawalModule`.
     * @dev Only callable by keeper role.
     * @param _withdrawalModule Address of `kHYPEWithdrawalModule`.
     * @param _amount Amount of token0 reserves to withdraw from STEX pool.
     */
    function unstakeToken0Reserves(address _withdrawalModule, uint256 _amount) external onlyKeeper {
        IWithdrawalModule(_withdrawalModule).unstakeToken0Reserves(_amount);
    }

    /**
     * @notice Withdraw `_amountToken1` of token1 reserves from pool via `_withdrawalModule`,
     *         and supply to its respective lending pool integration.
     * @dev Only callable by keeper role.
     * @param _withdrawalModule Address of `kHYPEWithdrawalModule`.
     * @param _amountToken1 Amount of token1 reserves to withdraw from STEX pool.
     */
    function supplyToken1ToLendingPool(address _withdrawalModule, uint256 _amountToken1) external onlyKeeper {
        IWithdrawalModule(_withdrawalModule).supplyToken1ToLendingPool(_amountToken1);
    }

    /**
     * @notice Withdraw `_amountToken1` of token1 from lending pool integration,
     *         and transfer it back to the respective STEX pool.
     * @dev Only callable by keeper role.
     * @param _withdrawalModule Address of `kHYPEWithdrawalModule`.
     * @param _amountToken1 Amount of token1 reserves to withdraw from lending pool.
     */
    function withdrawToken1FromLendingPool(address _withdrawalModule, uint256 _amountToken1) external onlyKeeper {
        IWithdrawalModule(_withdrawalModule)
            .withdrawToken1FromLendingPool(
                _amountToken1,
                address(0) // _recipient is unused, since it must the STEX pool
            );
    }

    /**
     * @notice Withdraw `_amountToken1` of token1 from STEX pool,
     *            and use it to net against pending LP withdrawals.
     * @dev Only callable by keeper role.
     * @param _withdrawalModule Address of `kHYPEWithdrawalModule`.
     * @param _amountToken1 Amount of token1 reserves to withdraw from STEX pool.
     */
    function settlePendingWithdrawalsWithPoolReserves(address _withdrawalModule, uint256 _amountToken1)
        external
        onlyKeeper
    {
        kHYPEWithdrawalModule(payable(_withdrawalModule)).settlePendingWithdrawalsWithPoolReserves(_amountToken1);
    }

    /**
     * @notice Atomically rebalances excess token0 STEX pool reserves into token1,
     *         at a price no worse than using kHYPE's StakingManager withdrawal queue.
     * @dev Only callable by keeper role.
     * @param _withdrawalModule Address of `kHYPEWithdrawalModule`.
     * @param _amountToken0 Amount of token0 reserves to rebalance into token1.
     * @param _recipient Address to receive `_amountToken0` of token0.
     * @param _rebalanceModule Address which should execute the rebalance.
     * @param _payload payload to `_rebalanceModule`.
     */
    function rebalanceToken0Reserves(
        address _withdrawalModule,
        uint256 _amountToken0,
        address _recipient,
        address _rebalanceModule,
        bytes calldata _payload
    ) external onlyKeeper {
        kHYPEWithdrawalModule(payable(_withdrawalModule))
            .rebalanceToken0Reserves(_amountToken0, _recipient, _rebalanceModule, _payload);
    }

    /**
     * @notice Unstake excess token0 balance through kHYPE's StakingManager.
     * @dev Only callable by keeper role.
     * @param _withdrawalModule Address of `kHYPEWithdrawalModule`.
     */
    function unstakeExcessToken0(address _withdrawalModule) external onlyKeeper {
        kHYPEWithdrawalModule(payable(_withdrawalModule)).unstakeExcessToken0();
    }
}
