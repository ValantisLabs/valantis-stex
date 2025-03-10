// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH9} from "./interfaces/IWETH9.sol";
import {ISTEXAMM} from "./interfaces/ISTEXAMM.sol";

/**
 * @notice Native token wrapper to deposit into Stake Exchange AMM.
 */
contract DepositWrapper {
    using SafeERC20 for IWETH9;

    /**
     *
     *  CUSTOM ERRORS
     *
     */
    error DepositWrapper__ZeroAddress();
    error DepositWrapper__constructor_invalidToken1();
    error DepositWrapper__receive_OnlyWETH9();

    /**
     *
     *  IMMUTABLES
     *
     */
    ISTEXAMM public immutable stex;
    IWETH9 public immutable weth;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _weth, address _stex) {
        if (_weth == address(0) || _stex == address(0)) {
            revert DepositWrapper__ZeroAddress();
        }
        stex = ISTEXAMM(_stex);
        weth = IWETH9(_weth);
        if (stex.token1() != _weth) {
            revert DepositWrapper__constructor_invalidToken1();
        }
    }

    /**
     *
     *  EXTERNAL FUNCTIONS
     *
     */
    receive() external payable {
        if (msg.sender != address(weth)) {
            revert DepositWrapper__receive_OnlyWETH9();
        }
    }

    /**
     * @notice Helper function which wraps native token before depositing.
     * @param _minShares Minimum amount of LP token required.
     * @param _deadline Block timestamp after which this call expires.
     * @param _recipient Address to mint LP tokens for.
     * @return shares Amount of LP tokens minted during deposit.
     */
    function depositFromNative(uint256 _minShares, uint256 _deadline, address _recipient)
        external
        payable
        returns (uint256 shares)
    {
        if (_recipient == address(0)) revert DepositWrapper__ZeroAddress();

        uint256 amount = msg.value;
        if (amount == 0) return 0;

        _wrapAndApprove(amount, address(stex));

        shares = stex.deposit(amount, _minShares, _deadline, _recipient);
    }

    /**
     *
     *  PRIVATE FUNCTIONS
     *
     */
    function _wrapAndApprove(uint256 amount, address to) private {
        weth.deposit{value: amount}();
        weth.forceApprove(to, amount);
    }
}
