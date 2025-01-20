// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ISovereignALM} from "@valantis-core/ALM/interfaces/ISovereignALM.sol";
import {ISwapFeeModuleMinimal} from "@valantis-core/swap-fee-modules/interfaces/ISwapFeeModule.sol";

interface IHAMM is ISovereignALM, ISwapFeeModuleMinimal {
    function pool() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function poolFeeRecipient1() external view returns (address);

    function poolFeeRecipient2() external view returns (address);

    function withdrawalModule() external view returns (address);

    function setSwapFeeParams(
        uint128 _reserve1Target,
        uint32 _feeMinBips,
        uint32 _feeMaxBips
    ) external;

    function setPoolManagerFeeBips(uint256 _poolManagerFeeBips) external;

    function claimPoolManagerFees() external;

    function unstakeToken0Reserves() external;

    function replenishPool(uint256 _amount) external;

    function swapOneToZeroEqualAmounts(
        uint256 _amountIn,
        address _recipient
    ) external returns (uint256 amountInUsed);

    function deposit(
        uint256 _amount,
        uint256 _minShares,
        uint256 _deadline,
        address _recipient
    ) external returns (uint256 shares);

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
