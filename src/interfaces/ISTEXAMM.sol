// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ISovereignALM} from "@valantis-core/ALM/interfaces/ISovereignALM.sol";
import {ISwapFeeModuleMinimal} from "@valantis-core/swap-fee-modules/interfaces/ISwapFeeModule.sol";

interface ISTEXAMM is ISovereignALM {
    event SwapFeeModuleProposed(address swapFeeModule, uint256 startTimestamp);

    event SwapFeeModuleProposalCancelled();

    event SwapFeeModuleSet(address swapFeeModule);

    event WithdrawalModuleProposed(address withdrawalModule, uint256 startTimestamp);

    event WithdrawalModuleProposalCancelled();

    event WithdrawalModuleSet(address withdrawalModule);

    event PoolManagerFeeSet(uint256 poolManagerFeeBips);

    event PoolManagerFeesClaimed(uint256 fee0, uint256 fee1);

    event Token0ReservesUnstaked(uint256 reserve0);

    event Deposit(address indexed sender, address indexed recipient, uint256 amountToken1, uint256 shares);

    event Withdraw(
        address indexed sender, address indexed recipient, uint256 amountToken0, uint256 amountToken1, uint256 shares
    );

    function isLocked() external view returns (bool);

    function pool() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function poolFeeRecipient1() external view returns (address);

    function poolFeeRecipient2() external view returns (address);

    function withdrawalModule() external view returns (address);

    function pause() external;

    function unpause() external;

    function proposeSwapFeeModule(address _swapFeeModule, uint256 _timelockDelay) external;

    function cancelSwapFeeModuleProposal() external;

    function setProposedSwapFeeModule() external;

    function proposeWithdrawalModule(address withdrawalModule_) external;

    function cancelWithdrawalModuleProposal() external;

    function setProposedWithdrawalModule() external;

    function setPoolManagerFeeBips(uint256 _poolManagerFeeBips) external;

    function claimPoolManagerFees() external;

    function unstakeToken0Reserves(uint256 _unstakeAmountToken0) external;

    function supplyToken1Reserves(uint256 _amount1) external;

    function getAmountOut(address _tokenIn, uint256 _amountIn, bool _isInstantWithdraw)
        external
        view
        returns (uint256 amountOut);

    function deposit(uint256 _amount, uint256 _minShares, uint256 _deadline, address _recipient)
        external
        returns (uint256 shares);

    function withdraw(
        uint256 _shares,
        uint256 _amount0Min,
        uint256 _amount1Min,
        uint256 _deadline,
        address _recipient,
        bool _unwrapToNativeToken,
        bool _isInstantWithdrawal
    ) external returns (uint256 amount0, uint256 amount1);
}
