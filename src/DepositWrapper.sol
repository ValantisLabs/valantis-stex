// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH9} from "./interfaces/IWETH9.sol";
import {IHAMM} from "./interfaces/IHAMM.sol";

contract DepositWrapper {
    using SafeERC20 for IWETH9;

    IHAMM public immutable hamm;
    IWETH9 public immutable weth;

    constructor(address _weth, address _hamm) {
        hamm = IHAMM(_hamm);
        weth = IWETH9(_weth);
    }

    function depositFromNative(
        uint256 _minShares,
        uint256 _deadline,
        address _recipient
    ) external payable returns (uint256 shares) {
        uint256 amount = msg.value;
        if (amount == 0) return 0;

        _wrapAndApprove(amount);

        shares = hamm.deposit(amount, _minShares, _deadline, _recipient);
    }

    function swapFromNative(
        address _recipient
    ) external payable returns (uint256 amountInUsed) {
        uint256 amount = msg.value;
        if (amount == 0) return 0;

        _wrapAndApprove(amount);

        amountInUsed = hamm.swapOneToZeroEqualAmounts(amount, _recipient);

        weth.forceApprove(address(hamm), 0);
    }

    function _wrapAndApprove(uint256 amount) private {
        weth.deposit{value: amount}();
        weth.forceApprove(address(hamm), amount);
    }
}
