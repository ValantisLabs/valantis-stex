// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

interface IWithdrawalModule {
    function burnAfterWithdraw(
        uint256 amountToken0,
        address recipient
    ) external;

    function burnAfterSwap(uint256 amountToken0) external;
}
