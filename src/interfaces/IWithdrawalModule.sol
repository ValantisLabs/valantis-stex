// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LPWithdrawalRequest} from "../structs/WithdrawalModuleStructs.sol";
import {ILendingModule} from "./ILendingModule.sol";

interface IWithdrawalModule {
    function overseer() external view returns (address);

    function lendingModule() external view returns (ILendingModule);

    function stex() external view returns (address);

    function amountToken0PendingUnstaking() external view returns (uint256);

    function amountToken1LendingPool() external view returns (uint256);

    function amountToken1PendingLPWithdrawal() external view returns (uint256);

    function amountToken1ClaimableLPWithdrawal() external view returns (uint256);

    function cumulativeAmountToken1ClaimableLPWithdrawal() external view returns (uint256);

    function convertToToken0(uint256 _amountToken1) external view returns (uint256);

    function convertToToken1(uint256 _amountToken0) external view returns (uint256);

    function token0SharesToBalance(uint256 _shares) external view returns (uint256);

    function token0BalanceToShares(uint256 _balance) external view returns (uint256);

    function token0SharesOf(address _account) external view returns (uint256);

    function getLPWithdrawals(uint256 _idLPWithdrawal) external view returns (LPWithdrawalRequest memory);

    function unstakeToken0Reserves(uint256 _unstakeAmountToken0) external;

    function burnToken0AfterWithdraw(uint256 _amountToken0, address _recipient) external;

    function withdrawToken1FromLendingPool(uint256 _amountToken1, address _recipient) external;
}
