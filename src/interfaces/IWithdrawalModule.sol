// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LPWithdrawalRequest} from "../structs/WithdrawalModuleStructs.sol";
import {ILendingModule} from "./ILendingModule.sol";

interface IWithdrawalModule {
    function overseer() external view returns (address);

    function lendingModule() external view returns (ILendingModule);

    function stex() external view returns (address);

    function amountToken0SharesPendingUnstakingLPWithdrawal() external view returns (uint256);

    function amountToken1LendingPool() external view returns (uint256);

    function amountToken0SharesPreUnstakingLPWithdrawal() external view returns (uint256);

    function amountToken0SharesPendingUnstaking() external view returns (uint256);

    function convertToToken0(uint256 _amountToken1) external view returns (uint256);

    function convertToToken1(uint256 _amountToken0) external view returns (uint256);

    function token0SharesToBalance(uint256 _shares) external view returns (uint256);

    function token0BalanceToShares(uint256 _balance) external view returns (uint256);

    function token0SharesOf(address _account) external view returns (uint256);

    function getLPWithdrawals(uint256 _idLPWithdrawal) external view returns (LPWithdrawalRequest memory);

    function epochExchangeRate(uint256 _epochId) external view returns (uint256);

    function unstakeToken0Reserves(uint256 _amountToken0) external;

    function addClaimForPreUnstakingShares(uint256 _amountToken0, address _recipient) external;

    function withdrawToken1FromLendingPool(uint256 _amountToken1, address _recipient) external;

    function amount0Correction() external view returns (int256);

    function addClaimForPendingUnstakingShares(uint256 _shares, address _recipient) external;
}
