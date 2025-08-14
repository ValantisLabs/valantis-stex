// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";

import {ProtocolFactory} from "@valantis-core/protocol-factory/ProtocolFactory.sol";
import {SwapFeeModuleData} from "@valantis-core/swap-fee-modules/interfaces/ISwapFeeModule.sol";
import {SovereignPoolFactory} from "@valantis-core/pools/factories/SovereignPoolFactory.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import {ALMLiquidityQuoteInput, ALMLiquidityQuote} from "@valantis-core/ALM/structs/SovereignALMStructs.sol";
import {SovereignPoolSwapParams} from "@valantis-core/pools/structs/SovereignPoolStructs.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {WETH} from "@solmate/tokens/WETH.sol";

import {STEXAMM} from "src/STEXAMM.sol";
import {StepwiseFeeModule} from "src/swap-fee-modules/StepwiseFeeModule.sol";
import {stHYPEWithdrawalModule} from "src/withdrawal-modules/stHYPEWithdrawalModule.sol";
import {MockOverseer} from "src/mocks/sthype/MockOverseer.sol";
import {MockStHype} from "src/mocks/sthype/MockStHype.sol";

contract STEXAMMStepwiseFeeModuleTest is Test {
    STEXAMM stex;

    StepwiseFeeModule stepwiseFeeModule;
    stHYPEWithdrawalModule withdrawalModule;

    ProtocolFactory protocolFactory;

    WETH weth;
    MockStHype token0;

    MockOverseer overseer;

    address public poolFeeRecipient1 = makeAddr("POOL_FEE_RECIPIENT_1");
    address public poolFeeRecipient2 = makeAddr("POOL_FEE_RECIPIENT_2");

    address public owner = makeAddr("OWNER");
    uint256 public constant BIPS = 10_000;

    ISovereignPool pool;

    function setUp() public {
        token0 = new MockStHype();
        weth = new WETH();

        overseer = new MockOverseer(address(token0));

        protocolFactory = new ProtocolFactory(address(this));

        address sovereignPoolFactory = address(new SovereignPoolFactory());
        protocolFactory.setSovereignPoolFactory(sovereignPoolFactory);

        withdrawalModule = new stHYPEWithdrawalModule(address(overseer), makeAddr("wstHYPE"), address(this));

        stepwiseFeeModule = new StepwiseFeeModule(owner);
        assertEq(stepwiseFeeModule.owner(), owner);

        stex = new STEXAMM(
            "Stake Exchange LP",
            "STEX LP",
            address(token0),
            address(weth),
            address(stepwiseFeeModule),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(withdrawalModule),
            0
        );
        withdrawalModule.setSTEX(address(stex));
        assertEq(withdrawalModule.stex(), address(stex));

        vm.startPrank(owner);
        stepwiseFeeModule.setPool(stex.pool());

        vm.expectRevert(StepwiseFeeModule.StepwiseFeeModule__setPool_AlreadySet.selector);
        stepwiseFeeModule.setPool(makeAddr("MOCK_SOVEREIGN_POOL"));

        vm.stopPrank();

        pool = ISovereignPool(stex.pool());

        vm.deal(address(this), 300 ether);
        weth.deposit{value: 100 ether}();
        uint256 shares = token0.mint{value: 100 ether}(address(this));
        assertEq(shares, 100 ether);
        assertEq(token0.totalSupply(), shares);
        assertEq(token0.balanceOf(address(this)), shares);
        assertEq(address(token0).balance, 100 ether);

        token0.approve(address(pool), 100 ether);
        weth.approve(address(pool), type(uint256).max);
    }

    function testSetStepwiseSwapFeeParams_revertsWhenNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        stepwiseFeeModule.setFeeParamsToken0(10 ether, 100 ether, new uint32[](0));
    }

    function testSetStepwiseSwapFeeParams_revertsWhenZeroSteps() public {
        vm.expectRevert(
            abi.encodeWithSelector(StepwiseFeeModule.StepwiseFeeModule__setFeeParamsToken0__ZeroSteps.selector)
        );
        _setStepwiseSwapFeeParams(10 ether, 100 ether, new uint32[](0));
    }

    function testSetStepwiseSwapFeeParams_revertsWhenFeeTooHigh() public {
        vm.expectRevert(
            abi.encodeWithSelector(StepwiseFeeModule.StepwiseFeeModule__setFeeParamsToken0__FeeTooHigh.selector)
        );
        uint256 minThreshold = 10 ether;
        uint256 maxThreshold = 100 ether;
        uint32[] memory feeStepsInBips = new uint32[](2);
        feeStepsInBips[0] = 5;
        feeStepsInBips[1] = 5001;
        _setStepwiseSwapFeeParams(minThreshold, maxThreshold, feeStepsInBips);
    }

    function testSetStepwiseSwapFeeParams_revertsWhenFeeTooLow() public {
        vm.expectRevert(
            abi.encodeWithSelector(StepwiseFeeModule.StepwiseFeeModule__setFeeParamsToken0__FeeTooLow.selector)
        );
        uint256 minThreshold = 10 ether;
        uint256 maxThreshold = 100 ether;
        uint32[] memory feeStepsInBips = new uint32[](2);
        feeStepsInBips[0] = 0;
        feeStepsInBips[1] = 5;
        _setStepwiseSwapFeeParams(minThreshold, maxThreshold, feeStepsInBips);
    }

    function testSetStepwiseSwapFeeParams_revertsWhenThresholdFlipped() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                StepwiseFeeModule
                    .StepwiseFeeModule__setFeeParamsToken0__MinToken1ThresholdAboveMaxToken1Threshold
                    .selector
            )
        );
        uint256 minThreshold = 100 ether;
        uint256 maxThreshold = 10 ether;
        uint32[] memory feeStepsInBips = new uint32[](2);
        feeStepsInBips[0] = 1;
        feeStepsInBips[1] = 5;
        _setStepwiseSwapFeeParams(minThreshold, maxThreshold, feeStepsInBips);
    }

    function testSetStepwiseSwapFeeParams_revertsWhenThresholdEqual() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                StepwiseFeeModule
                    .StepwiseFeeModule__setFeeParamsToken0__MinToken1ThresholdAboveMaxToken1Threshold
                    .selector
            )
        );
        uint256 minThreshold = 100 ether;
        uint256 maxThreshold = 100 ether;
        uint32[] memory feeStepsInBips = new uint32[](2);
        feeStepsInBips[0] = 1;
        feeStepsInBips[1] = 5;
        _setStepwiseSwapFeeParams(minThreshold, maxThreshold, feeStepsInBips);
    }

    function testSetStepwiseSwapFeeParams_revertsWhenThresholdZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                StepwiseFeeModule.StepwiseFeeModule__setFeeParamsToken0__MinToken1ThresholdZero.selector
            )
        );
        uint256 minThreshold = 0 ether;
        uint256 maxThreshold = 100 ether;
        uint32[] memory feeStepsInBips = new uint32[](2);
        feeStepsInBips[0] = 1;
        feeStepsInBips[1] = 5;
        _setStepwiseSwapFeeParams(minThreshold, maxThreshold, feeStepsInBips);

        minThreshold = 10 ether;
        maxThreshold = 0;
        vm.expectRevert(StepwiseFeeModule.StepwiseFeeModule__setFeeParamsToken0__MaxToken1ThresholdZero.selector);
        _setStepwiseSwapFeeParams(minThreshold, maxThreshold, feeStepsInBips);
    }

    function testSetStepwiseSwapFeeParams_revertsWhenFeeStepsNotMonotonicallyNonDecreasing() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                StepwiseFeeModule.StepwiseFeeModule__setFeeParamsToken0__FeeStepsNotMonotonicallyNonDecreasing.selector
            )
        );
        uint256 maxThreshold = 100 ether;
        uint256 minThreshold = 10 ether;
        uint32[] memory feeStepsInBips = new uint32[](2);
        feeStepsInBips[0] = 5;
        feeStepsInBips[1] = 4;
        _setStepwiseSwapFeeParams(minThreshold, maxThreshold, feeStepsInBips);
    }

    function testSetStepwiseSwapFeeParams_deletesOldFeeBipsToken0Array() public {
        uint32[] memory feeBipsToken0 = new uint32[](5);
        feeBipsToken0[0] = 1;
        feeBipsToken0[1] = 2;
        feeBipsToken0[2] = 3;
        feeBipsToken0[3] = 4;
        feeBipsToken0[4] = 5;

        _setStepwiseSwapFeeParams(10 ether, 100 ether, feeBipsToken0);
        assertEq(stepwiseFeeModule.minThresholdToken1(), 10 ether);
        assertEq(stepwiseFeeModule.maxThresholdToken1(), 100 ether);
        assertEq(stepwiseFeeModule.numStepsToken0FeeCurve(), 5);
        uint32[] memory feeBipsToken0Set = stepwiseFeeModule.getToken0FeeInBips();
        assertEq(feeBipsToken0Set.length, 5);
        assertEq(feeBipsToken0Set[0], 1);
        assertEq(feeBipsToken0Set[1], 2);
        assertEq(feeBipsToken0Set[2], 3);
        assertEq(feeBipsToken0Set[3], 4);
        assertEq(feeBipsToken0Set[4], 5);

        uint32[] memory feeBipsToken0New = new uint32[](2);
        feeBipsToken0New[0] = 12;
        feeBipsToken0New[1] = 23;

        _setStepwiseSwapFeeParams(5 ether, 25 ether, feeBipsToken0New);
        assertEq(stepwiseFeeModule.minThresholdToken1(), 5 ether);
        assertEq(stepwiseFeeModule.maxThresholdToken1(), 25 ether);
        assertEq(stepwiseFeeModule.numStepsToken0FeeCurve(), 2);
        feeBipsToken0Set = stepwiseFeeModule.getToken0FeeInBips();
        assertEq(feeBipsToken0Set.length, 2);
        assertEq(feeBipsToken0Set[0], 12);
        assertEq(feeBipsToken0Set[1], 23);
    }

    function testSwapTooMuchLiquidity() public {
        assertFalse(stex.isLocked());
        address recipient = makeAddr("RECIPIENT");
        _addPoolReserves(0 ether, 50 ether);
        // Reserve0 = 0 ether, Reserve1 = 50 ether
        uint256 maxToken1Threshold = 50 ether;
        uint256 minToken1Threshold = 10 ether;
        uint32[] memory steps = new uint32[](2);
        steps[0] = 5; // Fee is 5 bips <= token1 = 50 ether
        steps[1] = 10; // Fee is 10 bips <= token1 = 30 ether; or token0 swap size < 20.
        _setStepwiseSwapFeeParams(minToken1Threshold, maxToken1Threshold, steps);
        assertEq(stepwiseFeeModule.numStepsToken0FeeCurve(), 2);
        assertEq(stepwiseFeeModule.minThresholdToken1(), minToken1Threshold);
        assertEq(stepwiseFeeModule.maxThresholdToken1(), maxToken1Threshold);
        uint32[] memory feeBipsToken0 = stepwiseFeeModule.getToken0FeeInBips();
        assertEq(feeBipsToken0.length, 2);
        assertEq(feeBipsToken0[0], 5);
        assertEq(feeBipsToken0[1], 10);

        SovereignPoolSwapParams memory params;
        params.isZeroToOne = true;
        params.amountIn = 0.4 ether;
        params.deadline = block.timestamp;
        params.swapTokenOut = address(weth);
        params.recipient = recipient;

        // Swap some more up to the first tick, fee should stay 5 bips
        params.amountIn = 49 ether;
        SwapFeeModuleData memory swapFeeDataSameTick =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeDataSameTick.feeInBips, _transformFeeInBips(10));

        // At the tick, the next fee should be used
        params.amountIn = 50 ether;
        SwapFeeModuleData memory swapFeeDataNextTick =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeDataNextTick.feeInBips, _transformFeeInBips(10));

        params.amountIn = 500 ether;
        SwapFeeModuleData memory swapFeeDataLarge =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeDataLarge.feeInBips, _transformFeeInBips(10));
    }

    function testSimpleSwap() public {
        assertFalse(stex.isLocked());
        address recipient = makeAddr("RECIPIENT");
        _addPoolReserves(0 ether, 50 ether);
        // Reserve0 = 0 ether, Reserve1 = 50 ether
        uint256 maxToken1Threshold = 50 ether;
        uint256 minToken1Threshold = 10 ether;
        uint32[] memory steps = new uint32[](2);
        steps[0] = 5; // Fee is 5 bips <= token1 = 50 ether
        steps[1] = 10; // Fee is 10 bips <= token1 = 30 ether; or token0 swap size < 20.
        _setStepwiseSwapFeeParams(minToken1Threshold, maxToken1Threshold, steps);
        assertEq(stepwiseFeeModule.numStepsToken0FeeCurve(), 2);
        assertEq(stepwiseFeeModule.minThresholdToken1(), minToken1Threshold);
        assertEq(stepwiseFeeModule.maxThresholdToken1(), maxToken1Threshold);
        uint32[] memory feeBipsToken0 = stepwiseFeeModule.getToken0FeeInBips();
        assertEq(feeBipsToken0.length, 2);
        assertEq(feeBipsToken0[0], 5);
        assertEq(feeBipsToken0[1], 10);

        SovereignPoolSwapParams memory params;
        params.isZeroToOne = true;
        params.amountIn = 0.4 ether;
        params.deadline = block.timestamp;
        params.swapTokenOut = address(weth);
        params.recipient = recipient;

        // Small swap amount (total token0 = 0.4 ether ; token1 = 50 - 0.4)
        SwapFeeModuleData memory swapFeeData =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeData.feeInBips, _transformFeeInBips(5));

        // Swap some more up to the first tick, fee should stay 5 bips
        params.amountIn = 19.99999 ether;
        SwapFeeModuleData memory swapFeeDataSameTick =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeDataSameTick.feeInBips, _transformFeeInBips(5));

        // At the tick, the next fee should be used
        params.amountIn = 30 ether;
        SwapFeeModuleData memory swapFeeDataNextTick =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeDataNextTick.feeInBips, _transformFeeInBips(10));

        params.amountIn = 50 ether;
        SwapFeeModuleData memory swapFeeDataLarge =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeDataLarge.feeInBips, _transformFeeInBips(10));
    }

    function testMoreComplexFeeParams() public {
        assertFalse(stex.isLocked());
        address recipient = makeAddr("RECIPIENT");
        _addPoolReserves(100 ether, 0);
        uint32[] memory steps = new uint32[](4);
        uint256 minToken1Threshold = 10 ether;
        uint256 maxToken1Threshold = 70 ether;
        steps[0] = 5;
        steps[1] = 10;
        steps[2] = 15;
        steps[3] = 200;

        SovereignPoolSwapParams memory params;
        params.isZeroToOne = true;
        params.deadline = block.timestamp;
        params.swapTokenOut = address(weth);
        params.recipient = recipient;

        // Small size means we stay at the 0th tick
        params.amountIn = 0.4 ether;
        // revert before setting thresholds
        vm.expectRevert(StepwiseFeeModule.StepwiseFeeModule__getSwapFeeInBips_InvalidMinToken1Threshold.selector);
        stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));

        _setStepwiseSwapFeeParams(minToken1Threshold, maxToken1Threshold, steps);
        assertEq(stepwiseFeeModule.numStepsToken0FeeCurve(), 4);
        assertEq(stepwiseFeeModule.minThresholdToken1(), 10 ether);
        assertEq(stepwiseFeeModule.maxThresholdToken1(), 70 ether);
        uint32[] memory feeBipsToken0 = stepwiseFeeModule.getToken0FeeInBips();
        assertEq(feeBipsToken0.length, 4);
        assertEq(feeBipsToken0[0], 5);
        assertEq(feeBipsToken0[1], 10);
        assertEq(feeBipsToken0[2], 15);
        assertEq(feeBipsToken0[3], 200);

        SwapFeeModuleData memory swapFeeData;

        // Seed Token1 Liquidity
        // The steps are (70-10) / 4 = 15 ether wide. Starting at token1 reserves = 70.
        _addPoolReserves(0, 70 ether); // Token0 = 70

        // Zero Tick
        swapFeeData =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));

        assertEq(swapFeeData.feeInBips, _transformFeeInBips(5));

        // Charge minFee
        params.amountIn = 0.5 ether; // Charge Min Fee
        // First Tick
        console.log("first step");
        swapFeeData =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeData.feeInBips, _transformFeeInBips(5));
        // Pass the first bucket with maxThreshold - stepSize
        params.amountIn = 15 ether;
        // Past Threshold, first tick.
        swapFeeData =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeData.feeInBips, _transformFeeInBips(10));

        params.amountIn = 18 ether;
        // Between first and second tick
        swapFeeData =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeData.feeInBips, _transformFeeInBips(10));

        // Increase Token1 Liquidity. New Deposit lowers slippage.

        _addPoolReserves(0, 30 ether); // Token1 = 100
        // Back to first bucket with new deposit.
        params.amountIn = 1 ether;
        swapFeeData =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeData.feeInBips, _transformFeeInBips(5));

        params.amountIn = 44 ether; // Between first and second with new deposit
        swapFeeData =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeData.feeInBips, _transformFeeInBips(5));

        params.amountIn = 45 ether; // Between second and third with new deposit
        swapFeeData =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeData.feeInBips, _transformFeeInBips(10));

        params.amountIn = 60 ether; // Third tick
        swapFeeData =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeData.feeInBips, _transformFeeInBips(15));

        params.amountIn = 75 ether; // Max Fee, Fourth Tick
        swapFeeData =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeData.feeInBips, _transformFeeInBips(200));

        // The fee after reaching max reserves is the same as the fee in the tick before
        params.amountIn = 91 ether; // Max Fee, reach threshold
        swapFeeData =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeData.feeInBips, _transformFeeInBips(200));

        params.amountIn = 101 ether; // Max Fee for unrealistically large swap sizes
        swapFeeData =
            stepwiseFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertEq(swapFeeData.feeInBips, _transformFeeInBips(200));
    }

    function _setStepwiseSwapFeeParams(
        uint256 minToken0Threshold,
        uint256 maxToken0Threshold,
        uint32[] memory feeStepsInBips
    ) private {
        vm.startPrank(owner);
        stepwiseFeeModule.setFeeParamsToken0(minToken0Threshold, maxToken0Threshold, feeStepsInBips);
        vm.stopPrank();
    }

    function _addPoolReserves(uint256 amount0, uint256 amount1) private {
        (, uint256 preReserve1) = pool.getReserves();
        if (amount0 > 0) {
            token0.mint{value: amount0}(address(pool));
        }

        if (amount1 > 0) {
            weth.transfer(address(pool), amount1);
            (, uint256 postReserve1) = pool.getReserves();
            assertEq(postReserve1, preReserve1 + amount1);
        }
    }

    function _transformFeeInBips(uint256 feeInBips) private pure returns (uint256) {
        return (BIPS * feeInBips) / (BIPS - feeInBips);
    }
}
