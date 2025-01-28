// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {ProtocolFactory} from "@valantis-core/protocol-factory/ProtocolFactory.sol";
import {SwapFeeModuleData} from "@valantis-core/swap-fee-modules/interfaces/ISwapFeeModule.sol";
import {SovereignPoolFactory} from "@valantis-core/pools/factories/SovereignPoolFactory.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import {ALMLiquidityQuoteInput, ALMLiquidityQuote} from "@valantis-core/ALM/structs/SovereignALMStructs.sol";
import {SovereignPoolSwapParams} from "@valantis-core/pools/structs/SovereignPoolStructs.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {WETH} from "@solmate/tokens/WETH.sol";

import {HAMM} from "src/HAMM.sol";
import {HAMMSwapFeeModule} from "src/HAMMSwapFeeModule.sol";
import {WithdrawalModule} from "src/WithdrawalModule.sol";
import {MockOverseer} from "src/mocks/MockOverseer.sol";
import {MockStHype} from "src/mocks/MockStHype.sol";
import {DepositWrapper} from "src/DepositWrapper.sol";
import {FeeParams} from "src/structs/HAMMSwapFeeModuleStructs.sol";

contract HAMMTest is Test {
    HAMM hamm;
    HAMMSwapFeeModule swapFeeModule;
    WithdrawalModule withdrawalModule;

    DepositWrapper nativeWrapper;

    ProtocolFactory protocolFactory;

    WETH weth;
    MockStHype token0;

    MockOverseer overseer;

    address public poolFeeRecipient1 = makeAddr("POOL_FEE_RECIPIENT_1");
    address public poolFeeRecipient2 = makeAddr("POOL_FEE_RECIPIENT_2");

    address public owner = makeAddr("OWNER");

    ISovereignPool pool;

    function setUp() public {
        overseer = new MockOverseer();

        protocolFactory = new ProtocolFactory(address(this));

        address sovereignPoolFactory = address(new SovereignPoolFactory());
        protocolFactory.setSovereignPoolFactory(sovereignPoolFactory);

        withdrawalModule = new WithdrawalModule(address(overseer), address(this));

        swapFeeModule = new HAMMSwapFeeModule(owner, address(withdrawalModule));
        assertEq(swapFeeModule.owner(), owner);

        token0 = new MockStHype();
        weth = new WETH();

        hamm = new HAMM(
            address(token0),
            address(weth),
            address(swapFeeModule),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(withdrawalModule)
        );
        withdrawalModule.setHAMM(address(hamm));
        assertEq(withdrawalModule.hamm(), address(hamm));

        vm.startPrank(owner);
        swapFeeModule.setPool(hamm.pool());
        vm.stopPrank();

        vm.expectRevert(DepositWrapper.DepositWrapper__ZeroAddress.selector);
        new DepositWrapper(address(0), address(hamm));

        vm.expectRevert(DepositWrapper.DepositWrapper__ZeroAddress.selector);
        new DepositWrapper(address(weth), address(0));

        nativeWrapper = new DepositWrapper(address(weth), address(hamm));

        pool = ISovereignPool(hamm.pool());

        vm.deal(address(this), 300 ether);
        weth.deposit{value: 100 ether}();
        // Simulates a positive rebase
        vm.deal(address(token0), 20 ether);
        uint256 shares = token0.mint{value: 100 ether}(address(this));
        assertEq(shares, 100 ether);
        assertEq(token0.totalSupply(), shares);
        assertEq(token0.balanceOf(address(this)), shares);
        assertEq(address(token0).balance, 120 ether);

        token0.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);
    }

    function testDeploy() public {
        WithdrawalModule withdrawalModuleDeployment = new WithdrawalModule(address(overseer), address(this));
        assertEq(withdrawalModuleDeployment.overseer(), address(overseer));
        assertEq(withdrawalModuleDeployment.hamm(), address(0));
        assertEq(withdrawalModuleDeployment.owner(), address(this));

        HAMMSwapFeeModule swapFeeModuleDeployment = new HAMMSwapFeeModule(owner, address(withdrawalModuleDeployment));
        assertEq(swapFeeModuleDeployment.owner(), owner);
        assertEq(swapFeeModuleDeployment.withdrawalModule(), address(withdrawalModuleDeployment));

        vm.expectRevert(HAMM.HAMM__ZeroAddress.selector);
        new HAMM(
            address(0),
            address(weth),
            address(swapFeeModuleDeployment),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(withdrawalModuleDeployment)
        );
        vm.expectRevert(HAMM.HAMM__ZeroAddress.selector);
        new HAMM(
            address(token0),
            address(0),
            address(swapFeeModuleDeployment),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(withdrawalModuleDeployment)
        );
        vm.expectRevert(HAMM.HAMM__ZeroAddress.selector);
        new HAMM(
            address(token0),
            address(weth),
            address(0),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(withdrawalModuleDeployment)
        );
        vm.expectRevert(HAMM.HAMM__ZeroAddress.selector);
        new HAMM(
            address(token0),
            address(weth),
            address(swapFeeModuleDeployment),
            address(0),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(withdrawalModuleDeployment)
        );
        vm.expectRevert(HAMM.HAMM__ZeroAddress.selector);
        new HAMM(
            address(token0),
            address(weth),
            address(swapFeeModuleDeployment),
            address(protocolFactory),
            address(0),
            poolFeeRecipient2,
            owner,
            address(withdrawalModuleDeployment)
        );
        vm.expectRevert(HAMM.HAMM__ZeroAddress.selector);
        new HAMM(
            address(token0),
            address(weth),
            address(swapFeeModuleDeployment),
            address(protocolFactory),
            poolFeeRecipient1,
            address(0),
            owner,
            address(withdrawalModuleDeployment)
        );
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new HAMM(
            address(token0),
            address(weth),
            address(swapFeeModuleDeployment),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            address(0),
            address(withdrawalModuleDeployment)
        );
        vm.expectRevert(HAMM.HAMM__ZeroAddress.selector);
        new HAMM(
            address(token0),
            address(weth),
            address(swapFeeModuleDeployment),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(0)
        );

        HAMM hammDeployment = new HAMM(
            address(token0),
            address(weth),
            address(swapFeeModuleDeployment),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(withdrawalModuleDeployment)
        );
        assertEq(hammDeployment.token0(), address(token0));
        assertEq(hammDeployment.token1(), address(weth));
        assertEq(hammDeployment.poolFeeRecipient1(), poolFeeRecipient1);
        assertEq(hammDeployment.poolFeeRecipient2(), poolFeeRecipient2);
        assertEq(hammDeployment.owner(), owner);
        assertEq(hammDeployment.withdrawalModule(), address(withdrawalModuleDeployment));

        ISovereignPool poolDeployment = ISovereignPool(hammDeployment.pool());
        assertEq(poolDeployment.token0(), address(token0));
        assertEq(poolDeployment.token1(), address(weth));
        assertEq(poolDeployment.alm(), address(hammDeployment));
        assertEq(poolDeployment.swapFeeModule(), address(swapFeeModuleDeployment));
        assertEq(poolDeployment.poolManager(), address(hammDeployment));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        swapFeeModuleDeployment.setPool(address(poolDeployment));

        vm.startPrank(owner);
        swapFeeModuleDeployment.setPool(hammDeployment.pool());
        assertEq(swapFeeModuleDeployment.pool(), hammDeployment.pool());
        vm.expectRevert(HAMMSwapFeeModule.HAMMSwapFeeModule__setPool_alreadySet.selector);
        swapFeeModuleDeployment.setPool(makeAddr("MOCK_POOL"));
        vm.stopPrank();

        vm.expectRevert(DepositWrapper.DepositWrapper__ZeroAddress.selector);
        new DepositWrapper(address(0), address(hammDeployment));

        vm.expectRevert(DepositWrapper.DepositWrapper__ZeroAddress.selector);
        new DepositWrapper(address(weth), address(0));

        DepositWrapper nativeWrapperDeployment = new DepositWrapper(address(weth), address(hammDeployment));
        assertEq(address(nativeWrapperDeployment.hamm()), address(hammDeployment));
        assertEq(address(nativeWrapperDeployment.weth()), address(weth));
    }

    function testReceive() public {
        vm.expectRevert(HAMM.HAMM__receive_onlyWETH9.selector);
        address(hamm).call{value: 1 ether}("");

        vm.prank(address(weth));
        (bool success,) = address(hamm).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(hamm).balance, 1 ether);
    }

    function testSetSwapFeeParams() public {
        _setSwapFeeParams(1000, 7000, 1, 20);
    }

    function _setSwapFeeParams(
        uint32 minThresholdRatioBips,
        uint32 maxThresholdRatioBips,
        uint32 feeMinBips,
        uint32 feeMaxBips
    ) private {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        swapFeeModule.setSwapFeeParams(minThresholdRatioBips, maxThresholdRatioBips, feeMinBips, feeMaxBips);

        vm.startPrank(owner);

        vm.expectRevert(HAMMSwapFeeModule.HAMMSwapFeeModule__setSwapFeeParams_invalidMinThresholdRatio.selector);
        swapFeeModule.setSwapFeeParams(10_000, maxThresholdRatioBips, feeMinBips, feeMaxBips);

        vm.expectRevert(HAMMSwapFeeModule.HAMMSwapFeeModule__setSwapFeeParams_invalidMaxThresholdRatio.selector);
        swapFeeModule.setSwapFeeParams(minThresholdRatioBips, 10_000 + 1, feeMinBips, feeMaxBips);

        vm.expectRevert(HAMMSwapFeeModule.HAMMSwapFeeModule__setSwapFeeParams_inconsistentThresholdRatioParams.selector);
        swapFeeModule.setSwapFeeParams(maxThresholdRatioBips, maxThresholdRatioBips, feeMinBips, feeMaxBips);

        vm.expectRevert(HAMMSwapFeeModule.HAMMSwapFeeModule__setSwapFeeParams_invalidFeeMin.selector);
        swapFeeModule.setSwapFeeParams(minThresholdRatioBips, maxThresholdRatioBips, 5_000, feeMaxBips);

        vm.expectRevert(HAMMSwapFeeModule.HAMMSwapFeeModule__setSwapFeeParams_invalidFeeMax.selector);
        swapFeeModule.setSwapFeeParams(minThresholdRatioBips, maxThresholdRatioBips, feeMinBips, 5_000);

        vm.expectRevert(HAMMSwapFeeModule.HAMMSwapFeeModule__setSwapFeeParams_inconsistentFeeParams.selector);
        swapFeeModule.setSwapFeeParams(minThresholdRatioBips, maxThresholdRatioBips, 2, 1);

        swapFeeModule.setSwapFeeParams(minThresholdRatioBips, maxThresholdRatioBips, feeMinBips, feeMaxBips);

        (uint32 minThresholdRatio, uint32 maxThresholdRatio, uint32 feeMin, uint32 feeMax) = swapFeeModule.feeParams();
        assertEq(minThresholdRatio, minThresholdRatioBips);
        assertEq(maxThresholdRatio, maxThresholdRatioBips);
        assertEq(feeMin, feeMinBips);
        assertEq(feeMax, feeMaxBips);

        vm.stopPrank();
    }

    function testSetPoolManagerFeeBips() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        hamm.setPoolManagerFeeBips(1);

        vm.startPrank(owner);

        hamm.setPoolManagerFeeBips(1);
        assertEq(pool.poolManagerFeeBips(), 1);

        vm.stopPrank();
    }

    function testDeposit() public {
        address recipient = makeAddr("RECIPIENT");

        _deposit(1e18, recipient);
    }

    function _deposit(uint256 amount, address recipient) private {
        vm.expectRevert(HAMM.HAMM___checkDeadline_expired.selector);
        hamm.deposit(1e18, 0, block.timestamp - 1, recipient);

        // Test first deposit

        vm.expectRevert();
        hamm.deposit(1e9 - 1, 0, block.timestamp, recipient);

        vm.expectRevert(HAMM.HAMM__deposit_lessThanMinShares.selector);
        hamm.deposit(1e10, 1e10, block.timestamp, recipient);

        vm.expectRevert(HAMM.HAMM__deposit_zeroShares.selector);
        hamm.deposit(1e9, 0, block.timestamp, recipient);

        weth.approve(address(hamm), type(uint256).max);

        uint256 shares = hamm.deposit(1e9 + 1, 1, block.timestamp, recipient);
        assertEq(shares, 1);
        assertEq(hamm.balanceOf(address(1)), 1e9);
        assertEq(hamm.balanceOf(recipient), 1);
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 1e9 + 1);

        // Test normal deposit

        shares = hamm.deposit(amount, 0, block.timestamp, recipient);
        assertEq(hamm.balanceOf(address(1)), 1e9);
        assertEq(hamm.balanceOf(recipient), shares + 1);
        (reserve0, reserve1) = pool.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, amount + 1e9 + 1);
    }

    function testDeposit__FromNativeToken() public {
        testDeposit();

        address recipient = makeAddr("NATIVE_TOKEN_RECIPIENT");
        uint256 shares = nativeWrapper.depositFromNative(0, block.timestamp, recipient);
        // No native token has been sent
        assertEq(shares, 0);

        uint256 amount = 2 ether;
        (uint256 preReserve0, uint256 preReserve1) = pool.getReserves();
        shares = nativeWrapper.depositFromNative{value: amount}(0, block.timestamp, recipient);
        assertGt(shares, 0);
        assertEq(weth.allowance(address(nativeWrapper), address(hamm)), 0);
        assertEq(hamm.balanceOf(recipient), shares);
        (uint256 postReserve0, uint256 postReserve1) = pool.getReserves();
        assertEq(preReserve0, postReserve0);
        assertEq(preReserve1 + amount, postReserve1);
    }

    function testOnDepositLiquidityCallback() public {
        vm.expectRevert(HAMM.HAMM__OnlyPool.selector);
        hamm.onDepositLiquidityCallback(0, 0, new bytes(0));

        uint256 amount1 = 1e18;
        bytes memory data = abi.encode(address(this));
        weth.approve(address(hamm), amount1);

        vm.startPrank(address(pool));

        hamm.onDepositLiquidityCallback(0, amount1, data);

        assertEq(weth.balanceOf(address(pool)), amount1);

        vm.stopPrank();
    }

    function testWithdraw() public {
        address recipient = makeAddr("RECIPIENT");
        _deposit(1e18, recipient);

        uint256 shares = hamm.balanceOf(recipient);

        vm.expectRevert(HAMM.HAMM___checkDeadline_expired.selector);
        hamm.withdraw(1e18, 0, 0, block.timestamp - 1, recipient, false, false);

        vm.expectRevert(HAMM.HAMM__withdraw_zeroShares.selector);
        hamm.withdraw(0, 0, 0, block.timestamp, recipient, false, false);

        vm.expectRevert(HAMM.HAMM__ZeroAddress.selector);
        hamm.withdraw(shares, 0, 0, block.timestamp, address(0), false, false);

        vm.expectRevert(HAMM.HAMM__withdraw_insufficientToken0Withdrawn.selector);
        hamm.withdraw(shares, 1, 0, block.timestamp, recipient, false, false);

        vm.expectRevert(HAMM.HAMM__withdraw_insufficientToken1Withdrawn.selector);
        hamm.withdraw(shares, 0, 1e19, block.timestamp, recipient, false, false);

        vm.startPrank(recipient);

        uint256 snapshot1 = vm.snapshot();

        // Test regular withdrawal in liquid token1
        (uint256 preReserve0, uint256 preReserve1) = pool.getReserves();
        hamm.withdraw(shares, 0, 0, block.timestamp, recipient, false, false);
        assertEq(hamm.balanceOf(recipient), 0);
        (uint256 postReserve0, uint256 postReserve1) = pool.getReserves();
        assertEq(preReserve0, postReserve0);
        assertLt(postReserve1, preReserve1);

        // Test regular withdrawal in liquid native token (unwrapped token1)
        vm.revertTo(snapshot1);

        uint256 preBalance = recipient.balance;
        hamm.withdraw(shares, 0, 0, block.timestamp, recipient, true, false);
        assertEq(hamm.balanceOf(recipient), 0);
        uint256 postBalance = recipient.balance;
        assertGt(postBalance, preBalance);
        vm.stopPrank();
    }

    function testSwap() public {
        address recipient = makeAddr("RECIPIENT");
        _setSwapFeeParams(3000, 5000, 1, 30);

        // Test token0 -> token1 swap (low price impact)
        SovereignPoolSwapParams memory params;
        params.isZeroToOne = true;
        params.amountIn = 0.4 ether;
        params.deadline = block.timestamp;
        params.swapTokenOut = address(weth);
        params.recipient = recipient;

        // zero token1 liquidity
        vm.expectRevert(HAMMSwapFeeModule.HAMMSwapFeeModule__getSwapFeeInBips_ZeroReserveToken1.selector);
        hamm.getAmountOut(address(token0), params.amountIn);

        _addPoolReserves(0, 30 ether);

        uint256 amountOutEstimate = hamm.getAmountOut(address(token0), params.amountIn);
        (uint256 amountInUsed, uint256 amountOut) = pool.swap(params);
        assertLt(amountOut, withdrawalModule.convertToToken1(amountInUsed));
        assertLt(withdrawalModule.convertToToken0(amountOut), amountInUsed);
        assertEq(amountInUsed, 0.4 ether);
        assertEq(amountOut, amountOutEstimate);
        SwapFeeModuleData memory swapFeeData =
            swapFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        // price impact was low, so fee is still at the minimum
        assertEq(swapFeeData.feeInBips, 1);
        assertEq(weth.balanceOf(recipient), amountOut);

        // Test token0 -> token1 swap (medium price impact)
        params.amountIn = 5 ether;
        (amountInUsed, amountOut) = pool.swap(params);
        assertEq(amountInUsed, 5 ether);
        swapFeeData =
            swapFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        assertGt(swapFeeData.feeInBips, 1);
        assertLt(swapFeeData.feeInBips, 30);

        // Test token0 -> token1 swap (large price impact)
        params.amountIn = 10 ether;
        amountOutEstimate = hamm.getAmountOut(address(token0), params.amountIn);
        (amountInUsed, amountOut) = pool.swap(params);
        assertLt(amountOut, withdrawalModule.convertToToken1(amountInUsed));
        assertLt(withdrawalModule.convertToToken0(amountOut), amountInUsed);
        assertEq(amountOut, amountOutEstimate);
        swapFeeData = swapFeeModule.getSwapFeeInBips(address(token0), address(0), 0, address(0), new bytes(0));
        // This swap is large enough to push the fee to its maximum value of 30 bips
        assertEq(swapFeeData.feeInBips, 30);

        params.amountIn = 1 ether;
        // Fees in sovereign pool are applied as amountIn * BIPS / (BIPS + fee),
        // so we expect some discrepancies
        uint256 amountOutExpectedApprox = withdrawalModule.convertToToken1((params.amountIn * (10_000 - 30)) / 10_000);
        (amountInUsed, amountOut) = pool.swap(params);
        assertEq(amountInUsed, 1 ether);
        // Discrepancy should not exceed 1 bips
        assertEq((amountOut * 10_000) / amountOut, (amountOutExpectedApprox * 10_000) / amountOutExpectedApprox);

        // Test token1 -> token0 swap
        params.isZeroToOne = false;
        params.swapTokenOut = address(token0);

        // 1:1 exchange rate
        (amountInUsed, amountOut) = pool.swap(params);
        assertEq(amountInUsed, 1 ether);
        assertEq(amountOut, withdrawalModule.convertToToken0(1 ether));
        // amountOut is in shares
        assertApproxEqAbs(token0.sharesToAssets(amountOut), 1 ether, 1);
    }

    function testClaimPoolManagerFees() public {
        // Set 1% pool manager fee
        vm.prank(owner);
        hamm.setPoolManagerFeeBips(100);

        address recipient = makeAddr("RECIPIENT");
        _setSwapFeeParams(100, 200, 1, 30);

        _addPoolReserves(0, 30 ether);

        assertEq(token0.balanceOf(address(hamm)), 0);
        assertEq(weth.balanceOf(address(hamm)), 0);

        // Execute token0 -> token1 swap
        SovereignPoolSwapParams memory params;
        params.isZeroToOne = true;
        params.amountIn = 10 ether;
        params.deadline = block.timestamp;
        params.swapTokenOut = address(weth);
        params.recipient = recipient;
        (uint256 amountInUsed, uint256 amountOut) = pool.swap(params);
        assertEq(amountInUsed, 10 ether);
        assertEq(weth.balanceOf(recipient), amountOut);

        // Pool manager fee has automatically been transferred to HAMM during the swap
        assertGt(token0.balanceOf(address(hamm)), 0);
        assertEq(weth.balanceOf(address(hamm)), 0);

        // Claim pool manager fees
        hamm.claimPoolManagerFees();
        assertGt(token0.balanceOf(poolFeeRecipient1), 0);
        assertGt(token0.balanceOf(poolFeeRecipient2), 0);
        assertEq(token0.balanceOf(address(hamm)), 0);
    }

    function testUnstakeToken0Reserves() public {
        vm.expectRevert(HAMM.HAMM__OnlyWithdrawalModule.selector);
        hamm.unstakeToken0Reserves();

        _addPoolReserves(10 ether, 0);

        vm.startPrank(address(withdrawalModule));

        hamm.unstakeToken0Reserves();
    }

    function testGetLiquidityQuote() public view {
        // Test token1 -> token0
        ALMLiquidityQuoteInput memory input;
        input.amountInMinusFee = 123e18;
        ALMLiquidityQuote memory quote = hamm.getLiquidityQuote(input, new bytes(0), new bytes(0));
        assertEq(quote.amountInFilled, input.amountInMinusFee);
        // tokenOut=token0 balances represents shares of ETH
        assertEq(quote.amountOut, (input.amountInMinusFee * token0.totalSupply()) / address(token0).balance);

        // Test token0 -> token1
        input.isZeroToOne = true;
        quote = hamm.getLiquidityQuote(input, new bytes(0), new bytes(0));
        assertEq(quote.amountInFilled, input.amountInMinusFee);
        assertEq(quote.amountOut, (input.amountInMinusFee * address(token0).balance) / token0.totalSupply());
    }

    function testOnSwapCallback() public {
        vm.expectRevert(HAMM.HAMM__onSwapCallback_NotImplemented.selector);
        hamm.onSwapCallback(false, 0, 0);
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
}
