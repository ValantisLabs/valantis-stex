// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {ProtocolFactory} from "@valantis-core/protocol-factory/ProtocolFactory.sol";
import {SovereignPoolFactory} from "@valantis-core/pools/factories/SovereignPoolFactory.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import {ALMLiquidityQuoteInput, ALMLiquidityQuote} from "@valantis-core/ALM/structs/SovereignALMStructs.sol";
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

        withdrawalModule = new WithdrawalModule(address(overseer), address(this), address(this));

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
    }

    function testDeploy() public {
        WithdrawalModule withdrawalModuleDeployment =
            new WithdrawalModule(address(overseer), address(this), address(this));
        assertEq(withdrawalModuleDeployment.overseer(), address(overseer));
        assertEq(withdrawalModuleDeployment.initializer(), address(this));
        assertEq(withdrawalModuleDeployment.hamm(), address(0));
        assertEq(withdrawalModuleDeployment.owner(), address(this));

        HAMMSwapFeeModule swapFeeModuleDeployment = new HAMMSwapFeeModule(owner, address(withdrawalModuleDeployment));
        assertEq(swapFeeModuleDeployment.owner(), owner);

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
}
