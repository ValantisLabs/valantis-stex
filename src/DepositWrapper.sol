// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH9} from "./interfaces/IWETH9.sol";
import {IHAMM} from "./interfaces/IHAMM.sol";

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
    IHAMM public immutable hamm;
    IWETH9 public immutable weth;

    /**
     *
     *  CONSTRUCTOR
     *
     */
    constructor(address _weth, address _hamm) {
        if (_weth == address(0) || _hamm == address(0)) {
            revert DepositWrapper__ZeroAddress();
        }
        hamm = IHAMM(_hamm);
        weth = IWETH9(_weth);
        if (hamm.token1() != _weth) {
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

    function depositFromNative(
        uint256 _minShares,
        uint256 _deadline,
        address _recipient
    ) external payable returns (uint256 shares) {
        if (_recipient == address(0)) revert DepositWrapper__ZeroAddress();

        uint256 amount = msg.value;
        if (amount == 0) return 0;

        _wrapAndApprove(amount, address(hamm));

        shares = hamm.deposit(amount, _minShares, _deadline, _recipient);
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
