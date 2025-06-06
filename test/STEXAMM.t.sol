// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";

import {ProtocolFactory} from "@valantis-core/protocol-factory/ProtocolFactory.sol";
import {SwapFeeModuleData} from "@valantis-core/swap-fee-modules/interfaces/ISwapFeeModule.sol";
import {SovereignPoolFactory} from "@valantis-core/pools/factories/SovereignPoolFactory.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import {ALMLiquidityQuoteInput, ALMLiquidityQuote} from "@valantis-core/ALM/structs/SovereignALMStructs.sol";
import {SovereignPoolSwapParams} from "@valantis-core/pools/structs/SovereignPoolStructs.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {WETH} from "@solmate/tokens/WETH.sol";

import {STEXAMM} from "src/STEXAMM.sol";
import {STEXLens} from "src/STEXLens.sol";
import {STEXRatioSwapFeeModule} from "src/STEXRatioSwapFeeModule.sol";
import {stHYPEWithdrawalModule} from "src/stHYPEWithdrawalModule.sol";
import {MockOverseer} from "src/mocks/MockOverseer.sol";
import {MockStHype} from "src/mocks/MockStHype.sol";
import {MockLendingPool} from "src/mocks/MockLendingPool.sol";
import {AaveLendingModule} from "src/AaveLendingModule.sol";
import {DepositWrapper} from "src/DepositWrapper.sol";
import {FeeParams} from "src/structs/STEXRatioSwapFeeModuleStructs.sol";
import {LPWithdrawalRequest} from "src/structs/WithdrawalModuleStructs.sol";

contract STEXAMMTest is Test {
    STEXAMM stex;
    STEXLens stexLens;

    STEXRatioSwapFeeModule swapFeeModule;
    stHYPEWithdrawalModule withdrawalModule;

    DepositWrapper nativeWrapper;

    ProtocolFactory protocolFactory;

    WETH weth;
    MockStHype token0;

    MockOverseer overseer;

    MockLendingPool lendingPool;
    AaveLendingModule lendingModule;

    address public poolFeeRecipient1 = makeAddr("POOL_FEE_RECIPIENT_1");
    address public poolFeeRecipient2 = makeAddr("POOL_FEE_RECIPIENT_2");

    address public owner = makeAddr("OWNER");

    ISovereignPool pool;

    function setUp() public {
        token0 = new MockStHype();
        weth = new WETH();

        overseer = new MockOverseer(address(token0));

        protocolFactory = new ProtocolFactory(address(this));

        address sovereignPoolFactory = address(new SovereignPoolFactory());
        protocolFactory.setSovereignPoolFactory(sovereignPoolFactory);

        stexLens = new STEXLens();

        lendingPool = new MockLendingPool(address(weth));

        withdrawalModule = new stHYPEWithdrawalModule(address(overseer), address(this));

        swapFeeModule = new STEXRatioSwapFeeModule(owner);
        assertEq(swapFeeModule.owner(), owner);

        stex = new STEXAMM(
            "Stake Exchange LP",
            "STEX LP",
            address(token0),
            address(weth),
            address(swapFeeModule),
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
        swapFeeModule.setPool(stex.pool());
        vm.stopPrank();

        lendingModule = new AaveLendingModule(
            address(lendingPool),
            lendingPool.lendingPoolYieldToken(),
            address(weth),
            address(withdrawalModule),
            address(0x123),
            2
        );
        assertEq(lendingModule.yieldToken(), lendingPool.lendingPoolYieldToken());
        assertEq(lendingModule.asset(), address(weth));
        assertEq(lendingModule.tokenSweepManager(), address(0x123));
        assertEq(lendingModule.owner(), address(withdrawalModule));
        assertEq(lendingModule.referralCode(), 2);

        withdrawalModule.proposeLendingModule(address(lendingModule), 3 days);
        vm.warp(block.timestamp + 3 days);
        withdrawalModule.setProposedLendingModule();

        vm.expectRevert(DepositWrapper.DepositWrapper__ZeroAddress.selector);
        new DepositWrapper(address(0), address(stex));

        vm.expectRevert(DepositWrapper.DepositWrapper__ZeroAddress.selector);
        new DepositWrapper(address(weth), address(0));

        nativeWrapper = new DepositWrapper(address(weth), address(stex));

        pool = ISovereignPool(stex.pool());

        vm.deal(address(this), 300 ether);
        weth.deposit{value: 100 ether}();
        // Simulates a positive rebase
        //vm.deal(address(token0), 20 ether);
        uint256 shares = token0.mint{value: 100 ether}(address(this));
        assertEq(shares, 100 ether);
        assertEq(token0.totalSupply(), shares);
        assertEq(token0.balanceOf(address(this)), shares);
        assertEq(address(token0).balance, 100 ether);

        token0.approve(address(pool), 100 ether);
        weth.approve(address(pool), type(uint256).max);
    }

    function testDeploy() public {
        stHYPEWithdrawalModule withdrawalModuleDeployment = new stHYPEWithdrawalModule(address(overseer), address(this));
        assertEq(withdrawalModuleDeployment.overseer(), address(overseer));
        assertEq(withdrawalModuleDeployment.stex(), address(0));
        assertEq(withdrawalModuleDeployment.owner(), address(this));

        STEXRatioSwapFeeModule swapFeeModuleDeployment = new STEXRatioSwapFeeModule(owner);
        assertEq(swapFeeModuleDeployment.owner(), owner);

        vm.expectRevert(STEXAMM.STEXAMM__ZeroAddress.selector);
        new STEXAMM(
            "Stake Exchange LP",
            "STEX LP",
            address(0),
            address(weth),
            address(swapFeeModuleDeployment),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(withdrawalModuleDeployment),
            0
        );
        vm.expectRevert(STEXAMM.STEXAMM__ZeroAddress.selector);
        new STEXAMM(
            "Stake Exchange LP",
            "STEX LP",
            address(token0),
            address(0),
            address(swapFeeModuleDeployment),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(withdrawalModuleDeployment),
            0
        );
        vm.expectRevert(STEXAMM.STEXAMM__ZeroAddress.selector);
        new STEXAMM(
            "Stake Exchange LP",
            "STEX LP",
            address(token0),
            address(weth),
            address(0),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(withdrawalModuleDeployment),
            0
        );
        vm.expectRevert(STEXAMM.STEXAMM__ZeroAddress.selector);
        new STEXAMM(
            "Stake Exchange LP",
            "STEX LP",
            address(token0),
            address(weth),
            address(swapFeeModuleDeployment),
            address(0),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(withdrawalModuleDeployment),
            0
        );
        vm.expectRevert(STEXAMM.STEXAMM__ZeroAddress.selector);
        new STEXAMM(
            "Stake Exchange LP",
            "STEX LP",
            address(token0),
            address(weth),
            address(swapFeeModuleDeployment),
            address(protocolFactory),
            address(0),
            poolFeeRecipient2,
            owner,
            address(withdrawalModuleDeployment),
            0
        );
        vm.expectRevert(STEXAMM.STEXAMM__ZeroAddress.selector);
        new STEXAMM(
            "Stake Exchange LP",
            "STEX LP",
            address(token0),
            address(weth),
            address(swapFeeModuleDeployment),
            address(protocolFactory),
            poolFeeRecipient1,
            address(0),
            owner,
            address(withdrawalModuleDeployment),
            0
        );
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new STEXAMM(
            "Stake Exchange LP",
            "STEX LP",
            address(token0),
            address(weth),
            address(swapFeeModuleDeployment),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            address(0),
            address(withdrawalModuleDeployment),
            0
        );
        vm.expectRevert(STEXAMM.STEXAMM__ZeroAddress.selector);
        new STEXAMM(
            "Stake Exchange LP",
            "STEX LP",
            address(token0),
            address(weth),
            address(swapFeeModuleDeployment),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(0),
            0
        );

        STEXAMM stexDeployment = new STEXAMM(
            "Stake Exchange LP",
            "STEX LP",
            address(token0),
            address(weth),
            address(swapFeeModuleDeployment),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(withdrawalModuleDeployment),
            0
        );
        assertEq(stexDeployment.token0(), address(token0));
        assertEq(stexDeployment.token1(), address(weth));
        assertEq(stexDeployment.poolFeeRecipient1(), poolFeeRecipient1);
        assertEq(stexDeployment.poolFeeRecipient2(), poolFeeRecipient2);
        assertEq(stexDeployment.owner(), owner);
        assertEq(stexDeployment.withdrawalModule(), address(withdrawalModuleDeployment));

        ISovereignPool poolDeployment = ISovereignPool(stexDeployment.pool());
        assertEq(poolDeployment.token0(), address(token0));
        assertEq(poolDeployment.token1(), address(weth));
        assertEq(poolDeployment.alm(), address(stexDeployment));
        assertEq(poolDeployment.swapFeeModule(), address(swapFeeModuleDeployment));
        assertEq(poolDeployment.poolManager(), address(stexDeployment));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        swapFeeModuleDeployment.setPool(address(poolDeployment));

        vm.startPrank(owner);
        swapFeeModuleDeployment.setPool(stexDeployment.pool());
        assertEq(swapFeeModuleDeployment.pool(), stexDeployment.pool());
        vm.expectRevert(STEXRatioSwapFeeModule.STEXRatioSwapFeeModule__setPool_alreadySet.selector);
        swapFeeModuleDeployment.setPool(makeAddr("MOCK_POOL"));
        vm.stopPrank();

        vm.expectRevert(DepositWrapper.DepositWrapper__ZeroAddress.selector);
        new DepositWrapper(address(0), address(stexDeployment));

        vm.expectRevert(DepositWrapper.DepositWrapper__ZeroAddress.selector);
        new DepositWrapper(address(weth), address(0));

        DepositWrapper nativeWrapperDeployment = new DepositWrapper(address(weth), address(stexDeployment));
        assertEq(address(nativeWrapperDeployment.stex()), address(stexDeployment));
        assertEq(address(nativeWrapperDeployment.weth()), address(weth));
    }

    function testReceive() public {
        vm.expectRevert(STEXAMM.STEXAMM__receive_onlyWETH9.selector);
        (bool success,) = address(stex).call{value: 1 ether}("");
        assertTrue(success);

        vm.prank(address(weth));
        (success,) = address(stex).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(stex).balance, 1 ether);
    }

    function testPause() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        stex.pause();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        stex.unpause();

        vm.startPrank(owner);

        stex.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        stex.pause();

        stex.unpause();

        vm.expectRevert(Pausable.ExpectedPause.selector);
        stex.unpause();

        vm.stopPrank();
    }

    function testSwapFeeModuleProposal() public {
        address swapFeeModuleMock = makeAddr("MOCK_SWAP_FEE_MODULE");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        stex.proposeSwapFeeModule(swapFeeModuleMock, 3 days);

        vm.startPrank(owner);

        vm.expectRevert(STEXAMM.STEXAMM__ZeroAddress.selector);
        stex.proposeSwapFeeModule(address(0), 3 days);

        vm.expectRevert(STEXAMM.STEXAMM___verifyTimelockDelay_timelockTooLow.selector);
        stex.proposeSwapFeeModule(swapFeeModuleMock, 3 days - 1);
        vm.expectRevert(STEXAMM.STEXAMM___verifyTimelockDelay_timelockTooHigh.selector);
        stex.proposeSwapFeeModule(swapFeeModuleMock, 7 days + 1);

        stex.proposeSwapFeeModule(swapFeeModuleMock, 3 days);
        (address swapFeeModuleProposed, uint256 startTimestamp) = stex.swapFeeModuleProposal();
        assertEq(swapFeeModuleProposed, swapFeeModuleMock);
        assertEq(startTimestamp, block.timestamp + 3 days);

        vm.expectRevert(STEXAMM.STEXAMM__proposeSwapFeeModule_ProposalAlreadyActive.selector);
        stex.proposeSwapFeeModule(swapFeeModuleMock, 3 days);

        vm.stopPrank();

        uint256 snapshot = vm.snapshotState();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        stex.cancelSwapFeeModuleProposal();

        vm.startPrank(owner);

        stex.cancelSwapFeeModuleProposal();
        (swapFeeModuleProposed, startTimestamp) = stex.swapFeeModuleProposal();
        assertEq(swapFeeModuleProposed, address(0));
        assertEq(startTimestamp, 0);

        vm.stopPrank();

        vm.revertToState(snapshot);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        stex.setProposedSwapFeeModule();

        vm.startPrank(owner);

        vm.expectRevert(STEXAMM.STEXAMM__setProposedSwapFeeModule_Timelock.selector);
        stex.setProposedSwapFeeModule();

        vm.warp(block.timestamp + 3 days);

        stex.setProposedSwapFeeModule();
        assertEq(pool.swapFeeModule(), swapFeeModuleMock);

        (swapFeeModuleProposed, startTimestamp) = stex.swapFeeModuleProposal();
        assertEq(swapFeeModuleProposed, address(0));
        assertEq(startTimestamp, 0);

        vm.expectRevert(STEXAMM.STEXAMM__setProposedSwapFeeModule_InactiveProposal.selector);
        stex.setProposedSwapFeeModule();

        vm.stopPrank();
    }

    function testWithdrawalModuleProposal() public {
        address withdrawalModuleMock = makeAddr("MOCK_WITHDRAWAL_MODULE");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        stex.proposeWithdrawalModule(withdrawalModuleMock);

        vm.startPrank(owner);

        vm.expectRevert(STEXAMM.STEXAMM__ZeroAddress.selector);
        stex.proposeWithdrawalModule(address(0));

        stex.proposeWithdrawalModule(withdrawalModuleMock);
        (address withdrawalModuleProposed, uint256 startTimestamp) = stex.withdrawalModuleProposal();
        assertEq(withdrawalModuleProposed, withdrawalModuleMock);
        assertEq(startTimestamp, block.timestamp + 7 days);

        vm.expectRevert(STEXAMM.STEXAMM__proposeWithdrawalModule_ProposalAlreadyActive.selector);
        stex.proposeWithdrawalModule(withdrawalModuleMock);

        vm.stopPrank();

        uint256 snapshot = vm.snapshotState();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        stex.cancelWithdrawalModuleProposal();

        vm.startPrank(owner);

        stex.cancelWithdrawalModuleProposal();
        (withdrawalModuleProposed, startTimestamp) = stex.withdrawalModuleProposal();
        assertEq(withdrawalModuleProposed, address(0));
        assertEq(startTimestamp, 0);

        vm.stopPrank();

        vm.revertToState(snapshot);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        stex.setProposedWithdrawalModule();

        vm.startPrank(owner);

        vm.expectRevert(STEXAMM.STEXAMM__setProposedWithdrawalModule_Timelock.selector);
        stex.setProposedWithdrawalModule();

        vm.warp(block.timestamp + 7 days);

        stex.setProposedWithdrawalModule();
        assertEq(stex.withdrawalModule(), withdrawalModuleMock);

        (withdrawalModuleProposed, startTimestamp) = stex.withdrawalModuleProposal();
        assertEq(withdrawalModuleProposed, address(0));
        assertEq(startTimestamp, 0);

        vm.expectRevert(STEXAMM.STEXAMM__setProposedWithdrawalModule_InactiveProposal.selector);
        stex.setProposedWithdrawalModule();

        vm.stopPrank();
    }

    function testSetSwapFeeParams() public {
        _setSwapFeeParams(1000, 7000, 1, 20);
        _setSwapFeeParams(11_000, 200_000, 1, 4999);
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

        vm.expectRevert(
            STEXRatioSwapFeeModule.STEXRatioSwapFeeModule__setSwapFeeParams_inconsistentThresholdRatioParams.selector
        );
        swapFeeModule.setSwapFeeParams(maxThresholdRatioBips, maxThresholdRatioBips, feeMinBips, feeMaxBips);

        vm.expectRevert(STEXRatioSwapFeeModule.STEXRatioSwapFeeModule__setSwapFeeParams_invalidFeeMin.selector);
        swapFeeModule.setSwapFeeParams(minThresholdRatioBips, maxThresholdRatioBips, 5_000, feeMaxBips);

        vm.expectRevert(STEXRatioSwapFeeModule.STEXRatioSwapFeeModule__setSwapFeeParams_invalidFeeMax.selector);
        swapFeeModule.setSwapFeeParams(minThresholdRatioBips, maxThresholdRatioBips, feeMinBips, 5_000);

        vm.expectRevert(STEXRatioSwapFeeModule.STEXRatioSwapFeeModule__setSwapFeeParams_inconsistentFeeParams.selector);
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
        stex.setPoolManagerFeeBips(1);

        vm.startPrank(owner);

        stex.setPoolManagerFeeBips(1);
        assertEq(pool.poolManagerFeeBips(), 1);

        vm.stopPrank();
    }

    function testDeposit() public {
        address recipient = makeAddr("RECIPIENT");

        _deposit(1e18, recipient);
    }

    function _deposit(uint256 amount, address recipient) private {
        assertFalse(stex.isLocked());

        vm.prank(owner);
        stex.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        stex.deposit(1e18, 0, block.timestamp - 1, recipient);

        vm.prank(owner);
        stex.unpause();

        vm.expectRevert(STEXAMM.STEXAMM___checkDeadline_expired.selector);
        stex.deposit(1e18, 0, block.timestamp - 1, recipient);

        // Test first deposit

        vm.expectRevert();
        stex.deposit(1e3 - 1, 0, block.timestamp, recipient);

        vm.expectRevert(STEXAMM.STEXAMM__deposit_lessThanMinShares.selector);
        stex.deposit(1e10, 1e10, block.timestamp, recipient);

        vm.expectRevert(STEXAMM.STEXAMM__deposit_zeroShares.selector);
        stex.deposit(1e3, 0, block.timestamp, recipient);

        weth.approve(address(stex), type(uint256).max);

        uint256 sharesSimulation = stexLens.getSharesForDeposit(address(stex), 1e3 + 1);
        uint256 shares = stex.deposit(1e3 + 1, 1, block.timestamp, recipient);
        assertEq(shares, sharesSimulation);
        assertEq(shares, 1);
        assertEq(stex.balanceOf(address(1)), 1e3);
        assertEq(stex.balanceOf(recipient), 1);
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 1e3 + 1);

        // Test normal deposit

        sharesSimulation = stexLens.getSharesForDeposit(address(stex), amount);
        uint256 sharesSimulation2 =
            stexLens.getSharesForDepositAndPoolReserves(address(stex), amount, reserve0, reserve1);
        assertEq(sharesSimulation, sharesSimulation2);
        shares = stex.deposit(amount, 0, block.timestamp, recipient);
        assertEq(shares, sharesSimulation);
        assertEq(stex.balanceOf(address(1)), 1e3);
        assertEq(stex.balanceOf(recipient), shares + 1);
        (reserve0, reserve1) = pool.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, amount + 1e3 + 1);

        {
            (
                uint256 reserve0Pool,
                uint256 reserve0Unstaking,
                uint256 reserve1Pool,
                uint256 reserve1Lending,
                uint256 amount1PendingLPWithdrawal
            ) = stexLens.getAllReserves(address(stex));
            assertEq(reserve0Pool + reserve0Unstaking, reserve0);
            assertEq(reserve1Pool, reserve1);
            assertEq(reserve1Lending, 0);
            assertEq(amount1PendingLPWithdrawal, 0);
        }
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
        assertEq(weth.allowance(address(nativeWrapper), address(stex)), 0);
        assertEq(stex.balanceOf(recipient), shares);
        (uint256 postReserve0, uint256 postReserve1) = pool.getReserves();
        assertEq(preReserve0, postReserve0);
        assertEq(preReserve1 + amount, postReserve1);
    }

    function testDeposit__FromToken0() public {
        testDeposit();

        // AMM swap fee as 1 bips
        _setSwapFeeParams(3000, 5000, 1, 1);

        address recipient = makeAddr("MOCK_RECIPIENT_FROM_TOKEN0");

        token0.mint{value: 1 ether}(recipient);

        vm.startPrank(recipient);

        uint256 amountToken0 = 1 ether;
        token0.approve(address(nativeWrapper), amountToken0);

        vm.expectRevert(DepositWrapper.DepositWrapper__ZeroAddress.selector);
        nativeWrapper.depositFromToken0(amountToken0, amountToken0, 0, block.timestamp, address(0));

        // No state updates
        nativeWrapper.depositFromToken0(0, 0, 0, block.timestamp, recipient);
        assertEq(stex.balanceOf(recipient), 0);

        vm.expectRevert(bytes("Excessive swap amount"));
        stexLens.getMinAmountsForToken0Deposit(address(stex), 2 * amountToken0, 0, 0);

        (uint256 amountToken1Min, uint256 minShares) =
            stexLens.getMinAmountsForToken0Deposit(address(stex), amountToken0, 0, 0);

        uint256 shares =
            nativeWrapper.depositFromToken0(amountToken0, amountToken1Min, minShares, block.timestamp, recipient);
        assertEq(token0.balanceOf(address(nativeWrapper)), 0);
        assertEq(weth.balanceOf(address(nativeWrapper)), 0);
        assertEq(stex.balanceOf(recipient), minShares);
        assertEq(stex.balanceOf(recipient), shares);

        vm.stopPrank();
    }

    function testDeposit__WithUpdate() public {
        assertFalse(stex.isLocked());

        address recipient = makeAddr("RECIPIENT");

        // Mocks a completed unstake operation which needs to be sent back into pool through `update`
        vm.deal(address(withdrawalModule), 0.123 ether);
        assertEq(address(withdrawalModule).balance, 0.123 ether);

        weth.approve(address(stex), type(uint256).max);

        stex.deposit(10e18, 0, block.timestamp, recipient);

        // `update` must have been called
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 10e18 + 0.123 ether);
        assertEq(address(withdrawalModule).balance, 0);
        assertEq(weth.balanceOf(address(withdrawalModule)), 0);
    }

    function testOnDepositLiquidityCallback() public {
        vm.expectRevert(STEXAMM.STEXAMM__OnlyPool.selector);
        stex.onDepositLiquidityCallback(0, 0, new bytes(0));

        uint256 amount1 = 1e18;
        bytes memory data = abi.encode(address(this));
        weth.approve(address(stex), amount1);

        vm.startPrank(address(pool));

        stex.onDepositLiquidityCallback(0, amount1, data);

        assertEq(weth.balanceOf(address(pool)), amount1);

        vm.stopPrank();
    }

    function testWithdraw() public {
        assertFalse(stex.isLocked());

        address recipient = makeAddr("RECIPIENT");
        {
            (uint256 amount0, uint256 amount1) = stexLens.getAmountsForWithdraw(address(stex), 0, false);
            assertEq(amount0, 0);
            assertEq(amount1, 0);
        }
        _deposit(1e18, recipient);

        uint256 shares = stex.balanceOf(recipient);

        vm.expectRevert(STEXAMM.STEXAMM___checkDeadline_expired.selector);
        stex.withdraw(1e18, 0, 0, block.timestamp - 1, recipient, false, false);

        vm.expectRevert(STEXAMM.STEXAMM__withdraw_zeroShares.selector);
        stex.withdraw(0, 0, 0, block.timestamp, recipient, false, false);

        vm.expectRevert(STEXAMM.STEXAMM__ZeroAddress.selector);
        stex.withdraw(shares, 0, 0, block.timestamp, address(0), false, false);

        vm.expectRevert(STEXAMM.STEXAMM__withdraw_insufficientToken0Withdrawn.selector);
        stex.withdraw(shares, 1, 0, block.timestamp, recipient, false, false);

        vm.expectRevert(STEXAMM.STEXAMM__withdraw_insufficientToken1Withdrawn.selector);
        stex.withdraw(shares, 0, 1e19, block.timestamp, recipient, false, false);

        vm.startPrank(recipient);

        uint256 snapshot1 = vm.snapshotState();

        // Test regular withdrawal in liquid token1
        (uint256 preReserve0, uint256 preReserve1) = pool.getReserves();
        {
            (uint256 amount0Simulation, uint256 amount1Simulation) =
                stexLens.getAmountsForWithdraw(address(stex), shares, false);
            (uint256 amount0, uint256 amount1) = stex.withdraw(shares, 0, 0, block.timestamp, recipient, false, false);
            assertEq(amount0Simulation, amount0);
            assertEq(amount1Simulation, amount1);
        }
        assertEq(stex.balanceOf(recipient), 0);
        (uint256 postReserve0, uint256 postReserve1) = pool.getReserves();
        assertEq(preReserve0, postReserve0);
        assertLt(postReserve1, preReserve1);

        // Test regular withdrawal in liquid native token (unwrapped token1)
        vm.revertToState(snapshot1);

        uint256 preBalance = recipient.balance;
        stex.withdraw(shares, 0, 0, block.timestamp, recipient, true, false);
        assertEq(stex.balanceOf(recipient), 0);
        uint256 postBalance = recipient.balance;
        assertGt(postBalance, preBalance);
        vm.stopPrank();
    }

    function testWithdraw__WithdrawalModule() public {
        assertFalse(stex.isLocked());

        // Tests withdrawal where token0 is sent to unstake via withdrawal module
        address recipient = makeAddr("RECIPIENT");

        _deposit(10e18, recipient);

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 10e18 + 1e3 + 1);

        token0.mint{value: 10e18}(address(pool));

        (reserve0, reserve1) = pool.getReserves();
        assertEq(reserve1, 10e18 + 1e3 + 1);

        uint256 shares = stex.balanceOf(recipient);
        assertGt(shares, 0);

        vm.startPrank(recipient);

        (uint256 amount0, uint256 amount1) = stex.withdraw(shares, 0, 0, block.timestamp, recipient, false, false);
        assertEq(stex.balanceOf(recipient), 0);
        assertEq(weth.balanceOf(recipient), amount1);
        assertEq(token0.balanceOf(recipient), 0);
        assertEq(withdrawalModule.amountToken1PendingLPWithdrawal(), withdrawalModule.convertToToken1(amount0));
        assertEq(withdrawalModule.idLPWithdrawal(), 1);
        (address to, uint96 amountToken1, uint256 cumulativeAmount) = withdrawalModule.LPWithdrawals(0);
        assertEq(amountToken1, withdrawalModule.convertToToken1(amount0));
        assertEq(cumulativeAmount, 0);
        assertEq(to, recipient);

        (reserve0, reserve1) = pool.getReserves();

        vm.stopPrank();

        // Mocks the processing of unstaking token0 by direct transfer of ETH
        vm.deal(address(withdrawalModule), 20e18);
        // The following quantities are immediately updated after the ETH balance increase,
        // even before `update` is called
        assertEq(withdrawalModule.amountToken0PendingUnstaking(), 0);
        assertEq(withdrawalModule.amountToken1PendingLPWithdrawal(), 0);

        // Fulfills pending withdrawals and re-deposits remaining token1 amount into pool
        withdrawalModule.update();
        // token1 amount which was previously pending unstaking can now be claimed
        assertEq(withdrawalModule.amountToken1ClaimableLPWithdrawal(), amountToken1);
        // These values have already been updated after the ETH transfer
        assertEq(withdrawalModule.amountToken1PendingLPWithdrawal(), 0);
        assertEq(withdrawalModule.amountToken0PendingUnstaking(), 0);
        assertEq(withdrawalModule.cumulativeAmountToken1ClaimableLPWithdrawal(), amountToken1);
        // Surplus token1 amount was sent to pool
        {
            (uint256 reserve0Post, uint256 reserve1Post) = pool.getReserves();
            assertEq(reserve1Post, reserve1 + 20e18 - amountToken1);
            assertEq(reserve0Post, reserve0);
        }
        // amountToken1 ETH remains in the contract, to be claimed by previously pending LP withdrawal
        assertEq(withdrawalModule.amountToken1ClaimableLPWithdrawal(), amountToken1);

        // Claim LP's withdrawal request

        withdrawalModule.claim(0);
        assertEq(recipient.balance, amountToken1);
        assertEq(withdrawalModule.amountToken1ClaimableLPWithdrawal(), 0);
        (to, amountToken1, cumulativeAmount) = withdrawalModule.LPWithdrawals(0);
        assertEq(to, address(0));
        assertEq(amountToken1, 0);
        assertEq(cumulativeAmount, 0);

        vm.expectRevert(stHYPEWithdrawalModule.stHYPEWithdrawalModule__claim_alreadyClaimed.selector);
        withdrawalModule.claim(0);
    }

    function testWithdraw__FromLendingPool() public {
        assertFalse(stex.isLocked());

        address recipient = makeAddr("RECIPIENT");

        _setSwapFeeParams(3000, 5000, 1, 30);

        _deposit(10e18, recipient);

        token0.mint{value: 1e16}(address(pool));

        // transfer WETH reserves to pool, and then into lending protocol
        weth.transfer(address(pool), 2 ether);
        withdrawalModule.supplyToken1ToLendingPool(2 ether);
        assertEq(withdrawalModule.amountToken1LendingPool(), 2 ether);

        uint256 shares = stex.balanceOf(recipient) / 2;
        assertGt(shares, 0);

        vm.startPrank(recipient);

        address withdrawRecipient = makeAddr("WITHDRAW_RECIPIENT");

        uint256 snapshot = vm.snapshotState();

        (uint256 amount0, uint256 amount1) =
            stex.withdraw(shares, 0, 0, block.timestamp, withdrawRecipient, false, true);
        assertEq(amount0, 0);
        assertEq(weth.balanceOf(withdrawRecipient), amount1);

        vm.revertToState(snapshot);

        (amount0, amount1) = stex.withdraw(shares, 0, 0, block.timestamp, withdrawRecipient, true, true);
        assertEq(amount0, 0);
        assertEq(withdrawRecipient.balance, amount1);
    }

    function testWithdraw__InstantWithdrawal() public {
        assertFalse(stex.isLocked());

        address recipient = makeAddr("RECIPIENT");

        _setSwapFeeParams(3000, 5000, 1, 30);

        _deposit(10e18, recipient);

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 10e18 + 1e3 + 1);

        token0.mint{value: 1e16}(address(pool));

        (reserve0, reserve1) = pool.getReserves();
        assertEq(reserve1, 10e18 + 1e3 + 1);

        uint256 shares = stex.balanceOf(recipient) / 2;
        assertGt(shares, 0);

        vm.startPrank(recipient);

        // Instant withdrawals are entirely in token1, hence amount min of token0 must be 0
        vm.expectRevert(STEXAMM.STEXAMM__withdraw_insufficientToken0Withdrawn.selector);
        (uint256 amount0, uint256 amount1) = stex.withdraw(shares, 1, 0, block.timestamp, recipient, false, true);

        (uint256 amount0Simulation, uint256 amount1Simulation) =
            stexLens.getAmountsForWithdraw(address(stex), shares, true);
        (amount0, amount1) = stex.withdraw(shares, 0, 0, block.timestamp, recipient, false, true);
        assertEq(amount0Simulation, amount0);
        assertEq(amount1Simulation, amount1);
        assertEq(amount0, 0);
        assertGt(amount1, 0);
        assertEq(weth.balanceOf(recipient), amount1);

        vm.stopPrank();
    }

    function testWithdraw__InstantWithdrawal__FromLendingPool() public {
        assertFalse(stex.isLocked());

        address recipient = makeAddr("RECIPIENT");

        _setSwapFeeParams(3000, 5000, 1, 30);

        _deposit(10e18, recipient);

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 10e18 + 1e3 + 1);

        token0.mint{value: 10e18}(address(pool));

        (reserve0, reserve1) = pool.getReserves();
        assertEq(reserve1, 10e18 + 1e3 + 1);

        uint256 shares = stex.balanceOf(recipient) / 2;
        assertGt(shares, 0);

        vm.startPrank(recipient);

        // Instant withdrawals are entirely in token1, hence amount min of token0 must be 0
        vm.expectRevert(STEXAMM.STEXAMM__withdraw_insufficientToken0Withdrawn.selector);
        (uint256 amount0, uint256 amount1) = stex.withdraw(shares, 1, 0, block.timestamp, recipient, false, true);
        vm.stopPrank();

        // Supply a large fraction of token1 reserves into lending pool
        withdrawalModule.supplyToken1ToLendingPool(9e18);
        assertEq(lendingModule.assetBalance(), 9e18);

        vm.startPrank(recipient);

        (uint256 amount0Simulation, uint256 amount1Simulation) =
            stexLens.getAmountsForWithdraw(address(stex), shares, true);
        (amount0, amount1) = stex.withdraw(shares, 0, 0, block.timestamp, recipient, false, true);
        assertEq(amount0Simulation, amount0);
        assertEq(amount1Simulation, amount1);
        assertEq(amount0, 0);
        assertGt(amount1, 0);
        assertEq(weth.balanceOf(recipient), amount1);
        // All token1 reserves have been withdrawn from pool
        assertEq(weth.balanceOf(address(pool)), 0);
        assertLt(lendingModule.assetBalance(), 9e18);

        vm.stopPrank();
    }

    function testWithdraw__WithUpdate() public {
        assertFalse(stex.isLocked());

        address recipient = makeAddr("MOCK_RECIPIENT");

        _deposit(1e18, recipient);

        uint256 shares = stex.balanceOf(recipient);
        assertGt(shares, 0);

        token0.mint{value: 1e18}(address(pool));
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertGt(reserve0, 0);
        assertEq(reserve1, 1e18 + 1e3 + 1);

        vm.startPrank(recipient);

        // Mocks the processing of unstaking token0 by direct transfer of ETH
        vm.deal(address(withdrawalModule), 0.123 ether);

        stex.withdraw(shares / 2, 0, 0, block.timestamp, recipient, false, false);
        // WETH was transferred to the pool and recipient
        assertGt(weth.balanceOf(recipient), 0);
        assertEq(token0.balanceOf(recipient), 0);
        assertEq(weth.balanceOf(address(pool)), reserve1 + 0.123 ether - weth.balanceOf(recipient));
        assertEq(address(withdrawalModule).balance, 0);
        assertEq(weth.balanceOf(address(withdrawalModule)), 0);

        vm.stopPrank();
    }

    function testWithdraw__NoClaimOnToken0() public {
        address recipient1 = makeAddr("RECIPIENT_1");
        address recipient2 = makeAddr("RECIPIENT_2");

        _setSwapFeeParams(3000, 5000, 1, 30);

        // user 1 deposits
        _deposit(10 ether, recipient1);
        uint256 shares1 = stex.balanceOf(recipient1);
        assertGt(shares1, 0);

        // user 2 deposits
        stex.deposit(1 ether, 0, block.timestamp, recipient2);
        uint256 shares2 = stex.balanceOf(recipient2);
        assertGt(shares2, 0);

        // Replace 5e18 WETH with 5e18 LST (same effect as swaps with 0 fee)
        token0.mint{value: 5 ether}(address(pool));

        vm.prank(address(stex));
        pool.withdrawLiquidity(0, 5 ether, address(this), address(1), new bytes(0));
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 5 ether);
        assertEq(reserve1, 5 ether + 1 ether + 1e3 + 1);

        // user 1 withdraws (delayed withdraw)
        {
            vm.startPrank(recipient1);
            (uint256 amount0Simulation, uint256 amount1Simulation) =
                stexLens.getAmountsForWithdraw(address(stex), shares1, false);
            (uint256 amount0, uint256 amount1) = stex.withdraw(shares1, 0, 0, block.timestamp, recipient1, false, false);
            vm.stopPrank();
            assertEq(amount0Simulation, amount0);
            assertEq(amount1Simulation, amount1);
        }
        // No unstaking has happened
        assertEq(withdrawalModule.amountToken0PendingUnstaking(), 0);
        assertGt(withdrawalModule.amountToken1PendingLPWithdrawal(), 0);
        // user 1 is eligible to 10e18 WETH
        assertEq(withdrawalModule.amountToken1PendingLPWithdrawal() + weth.balanceOf(recipient1), 10 ether);

        (reserve0, reserve1) = pool.getReserves();
        assertEq(reserve0, 5 ether);
        assertEq(reserve1, 5 ether + 1 ether + 1e3 + 1 - weth.balanceOf(recipient1));

        // Replace 1e18 LST with 1e18 WETH (same effect as swaps with 0 fee)
        {
            uint256 preBalance = address(token0).balance;
            token0.burn(address(pool), token0.balanceToShares(1e18));
            // corrects token0.burn by lowering ETH balance accordingly
            vm.deal(address(token0), preBalance - 1e18);
        }

        weth.transfer(address(pool), 1e18);

        (reserve0, reserve1) = pool.getReserves();
        // There is a higher amount of token1 owed to recipient1 than pool's token0 reserves
        assertGt(withdrawalModule.amountToken1PendingLPWithdrawal(), reserve0);

        uint256 snapshot = vm.snapshotState();

        // user 2 withdraws (delayed withdraw)
        {
            vm.startPrank(recipient2);
            (uint256 amount0Simulation, uint256 amount1Simulation) =
                stexLens.getAmountsForWithdraw(address(stex), shares2, false);
            (uint256 amount0Withdraw, uint256 amount1Withdraw) =
                stex.withdraw(shares2, 0, 0, block.timestamp, recipient2, false, false);
            assertEq(amount0Simulation, amount0Withdraw);
            assertEq(amount1Simulation, amount1Withdraw);
            (reserve0, reserve1) = pool.getReserves();

            // user 2 has no claim on token0 reserves,
            // but can still withdraw its due token1 portion
            assertEq(amount0Withdraw, 0);
            assertEq(amount1Withdraw, 1e18);
            assertEq(weth.balanceOf(recipient2), 1e18);
        }

        vm.revertToState(snapshot);

        // user 2 withdraws (instant withdraw)
        {
            vm.startPrank(recipient2);
            (uint256 amount0Simulation, uint256 amount1Simulation) =
                stexLens.getAmountsForWithdraw(address(stex), shares2, true);
            (uint256 amount0Withdraw, uint256 amount1Withdraw) =
                stex.withdraw(shares2, 0, 0, block.timestamp, recipient2, false, true);
            assertEq(amount0Simulation, amount0Withdraw);
            assertEq(amount1Simulation, amount1Withdraw);
            (reserve0, reserve1) = pool.getReserves();

            // user 2 has no claim on token0 reserves,
            // but can still withdraw its due token1 portion
            assertEq(amount0Withdraw, 0);
            assertEq(amount1Withdraw, 1e18);
            assertEq(weth.balanceOf(recipient2), 1e18);
        }
    }

    function testSwap() public {
        assertFalse(stex.isLocked());

        address recipient = makeAddr("RECIPIENT");
        _setSwapFeeParams(3000, 5000, 1, 30);

        {
            uint256 amountOutSimulation = stex.getAmountOut(address(token0), 0, false);
            assertEq(amountOutSimulation, 0);
            amountOutSimulation = stex.getAmountOut(recipient, 1 ether, false);
            assertEq(amountOutSimulation, 0);
        }

        // Test token0 -> token1 swap (low price impact)
        SovereignPoolSwapParams memory params;
        params.isZeroToOne = true;
        params.amountIn = 0.4 ether;
        params.deadline = block.timestamp;
        params.swapTokenOut = address(weth);
        params.recipient = recipient;

        // zero token1 liquidity
        vm.expectRevert(STEXRatioSwapFeeModule.STEXRatioSwapFeeModule__getSwapFeeInBips_ZeroReserveToken1.selector);
        stex.getAmountOut(address(token0), params.amountIn, false);

        _addPoolReserves(0, 30 ether);

        uint256 amountOutEstimate = stex.getAmountOut(address(token0), params.amountIn, false);
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
        amountOutEstimate = stex.getAmountOut(address(token0), params.amountIn, false);
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
        // amountOut is 1:1, because token0 is rebase
        assertApproxEqAbs(amountOut, 1 ether, 1);
    }

    function testSwap__SplitAmountVsFullAmount() public {
        address recipient = makeAddr("RECIPIENT");
        _setSwapFeeParams(3000, 5000, 1, 30);

        _addPoolReserves(0, 30 ether);

        uint256 snapshot = vm.snapshotState();
        uint256 amountOutTotalSplitSwaps;

        // We will test two scenarios:
        // two split swaps, each with amountIn = 5 eth
        // one swap with full amountIn = 10 eth

        // token0 -> token1 split amount swap 1/2
        SovereignPoolSwapParams memory params;
        params.isZeroToOne = true;
        params.amountIn = 5 ether;
        params.deadline = block.timestamp;
        params.swapTokenOut = address(weth);
        params.recipient = recipient;

        uint256 amountOutEstimate = stex.getAmountOut(address(token0), params.amountIn, false);
        (uint256 amountInUsed, uint256 amountOut) = pool.swap(params);
        assertLt(amountOut, withdrawalModule.convertToToken1(amountInUsed));
        assertLt(withdrawalModule.convertToToken0(amountOut), amountInUsed);
        assertEq(amountInUsed, 5 ether);
        assertEq(amountOut, amountOutEstimate);
        SwapFeeModuleData memory swapFeeData =
            swapFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        amountOutTotalSplitSwaps += amountOut;

        // token0 -> token1 split amount swap 2/2
        params.amountIn = 5 ether;
        (amountInUsed, amountOut) = pool.swap(params);
        assertEq(amountInUsed, 5 ether);
        swapFeeData =
            swapFeeModule.getSwapFeeInBips(address(token0), address(0), params.amountIn, address(0), new bytes(0));
        amountOutTotalSplitSwaps += amountOut;

        vm.revertToState(snapshot);

        // Test token0 -> token1 swap with full amount
        params.amountIn = 10 ether;
        amountOutEstimate = stex.getAmountOut(address(token0), params.amountIn, false);
        (amountInUsed, amountOut) = pool.swap(params);
        assertLt(amountOut, withdrawalModule.convertToToken1(amountInUsed));
        assertLt(withdrawalModule.convertToToken0(amountOut), amountInUsed);
        assertEq(amountOut, amountOutEstimate);
        swapFeeData = swapFeeModule.getSwapFeeInBips(address(token0), address(0), 0, address(0), new bytes(0));
        // Split swaps yields strictly worse trade execution
        assertLt(amountOutTotalSplitSwaps, amountOut);
    }

    function testClaimPoolManagerFees() public {
        // Set 1% pool manager fee
        vm.prank(owner);
        stex.setPoolManagerFeeBips(100);

        address recipient = makeAddr("RECIPIENT");
        _setSwapFeeParams(100, 200, 1, 30);

        _addPoolReserves(0, 30 ether);

        assertEq(token0.balanceOf(address(stex)), 0);
        assertEq(weth.balanceOf(address(stex)), 0);

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

        // Mock token1 fee via donation
        weth.transfer(address(stex), 1 ether);

        // Pool manager fee has automatically been transferred to STEX during the swap
        assertGt(token0.balanceOf(address(stex)), 0);
        assertEq(weth.balanceOf(address(stex)), 1 ether);

        // Claim pool manager fees
        stex.claimPoolManagerFees();
        assertGt(token0.balanceOf(poolFeeRecipient1), 0);
        assertGt(token0.balanceOf(poolFeeRecipient2), 0);
        assertEq(weth.balanceOf(poolFeeRecipient1), 0.5 ether);
        assertEq(weth.balanceOf(poolFeeRecipient2), 0.5 ether);
        assertEq(token0.balanceOf(address(stex)), 0);
        assertEq(weth.balanceOf(address(stex)), 0);
    }

    function testUnstakeToken0Reserves() public {
        uint256 amountToken0ReservesInitial = token0.balanceOf(address(stex));
        vm.expectRevert(STEXAMM.STEXAMM__OnlyWithdrawalModule.selector);
        stex.unstakeToken0Reserves(amountToken0ReservesInitial);

        _addPoolReserves(10 ether, 0);

        uint256 amountToken0ReservesFinal = token0.balanceOf(address(pool));

        vm.startPrank(address(withdrawalModule));

        vm.expectRevert(STEXAMM.STEXAMM__unstakeToken0Reserves_amountCannotBeZero.selector);
        stex.unstakeToken0Reserves(0);

        vm.expectRevert(STEXAMM.STEXAMM__unstakeToken0Reserves_amountTooHigh.selector);
        stex.unstakeToken0Reserves(10 ether + 1);

        stex.unstakeToken0Reserves(amountToken0ReservesFinal);
        assertEq(token0.balanceOf(address(pool)), 0);
    }

    function testUnstakeToken0ReservesPartial() public {
        uint256 amountToken0ReservesInitial = token0.balanceOf(address(stex));
        vm.expectRevert(STEXAMM.STEXAMM__OnlyWithdrawalModule.selector);
        stex.unstakeToken0Reserves(amountToken0ReservesInitial);

        _addPoolReserves(10 ether, 0);
        uint256 amountToken0ReservesFinal = token0.balanceOf(address(pool));
        vm.startPrank(address(withdrawalModule));
        stex.unstakeToken0Reserves(amountToken0ReservesFinal / 2);
        assertApproxEqAbs(token0.balanceOf(address(pool)), amountToken0ReservesFinal / 2, 1);
    }

    function testSupplyToken1Reserves() public {
        uint256 amount = 1 ether;

        vm.expectRevert(STEXAMM.STEXAMM__OnlyWithdrawalModule.selector);
        stex.supplyToken1Reserves(amount);

        _addPoolReserves(0, 10 ether);

        vm.startPrank(address(withdrawalModule));

        stex.supplyToken1Reserves(amount);
        assertEq(weth.balanceOf(address(withdrawalModule)), amount);
    }

    function testGetLiquidityQuote() public {
        // Test token1 -> token0
        ALMLiquidityQuoteInput memory input;
        input.amountInMinusFee = 123e18;
        ALMLiquidityQuote memory quote = stex.getLiquidityQuote(input, new bytes(0), new bytes(0));
        assertEq(quote.amountInFilled, input.amountInMinusFee);
        // tokenOut=token0 balances represents shares of ETH
        assertEq(quote.amountOut, (input.amountInMinusFee * token0.totalSupply()) / address(token0).balance);

        vm.prank(owner);
        stex.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        stex.getLiquidityQuote(input, new bytes(0), new bytes(0));

        vm.prank(owner);
        stex.unpause();

        // Test token0 -> token1
        input.isZeroToOne = true;
        quote = stex.getLiquidityQuote(input, new bytes(0), new bytes(0));
        assertEq(quote.amountInFilled, input.amountInMinusFee);
        assertEq(quote.amountOut, (input.amountInMinusFee * address(token0).balance) / token0.totalSupply());
    }

    function testOnSwapCallback() public {
        vm.expectRevert(STEXAMM.STEXAMM__onSwapCallback_NotImplemented.selector);
        stex.onSwapCallback(false, 0, 0);
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
