// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {WETH} from "@solmate/tokens/WETH.sol";

import {AaveLendingModule} from "src/lending-modules/AaveLendingModule.sol";
import {kHYPEWithdrawalModule} from "src/withdrawal-modules/kHYPEWithdrawalModule.sol";
import {STEXLens} from "src/STEXLens.sol";
import {IRebalanceModule} from "src/interfaces/IRebalanceModule.sol";
import {MockLendingPool} from "src/mocks/MockLendingPool.sol";
import {MockStakingAccountant} from "src/mocks/kinetiq/MockStakingAccountant.sol";
import {MockStakingManager} from "src/mocks/kinetiq/MockStakingManager.sol";
import {LPWithdrawalRequest} from "src/structs/WithdrawalModuleStructs.sol";

contract MockPool {
    bool private _isLocked = false;

    ERC20Mock public token0;
    ERC20Mock public token1;

    bool public decreaseReserve0;
    bool public decreaseReserve1;

    constructor(address _token0, address _token1) {
        token0 = ERC20Mock(_token0);
        token1 = ERC20Mock(_token1);
    }

    function isLocked() external view returns (bool) {
        return _isLocked;
    }

    function setIsLocked(bool _value) external {
        _isLocked = _value;
    }

    function setDecreaseReserves(bool _value0, bool _value1) external {
        decreaseReserve0 = _value0;
        decreaseReserve1 = _value1;
    }

    function getReserves() external view returns (uint256 reserve0, uint256 reserve1) {
        reserve0 = token0.balanceOf(address(this));
        reserve1 = token1.balanceOf(address(this));

        if (decreaseReserve0) {
            reserve0 -= 1;
        }

        if (decreaseReserve1) {
            reserve1 -= 1;
        }
    }
}

contract MockRebalanceModule is IRebalanceModule {
    WETH weth;
    MockPool pool;

    constructor(WETH _weth, MockPool _pool) {
        weth = _weth;
        pool = _pool;
    }

    function rebalance(uint256 amountToken1Min, bytes calldata payload) external returns (bytes4) {
        (bool useWrongSelector, bool reduceToken0Reserves, bool reduceToken1Reserves, bool transferInsufficientAmount) =
            abi.decode(payload, (bool, bool, bool, bool));

        weth.transfer(msg.sender, transferInsufficientAmount ? amountToken1Min / 2 : amountToken1Min);

        if (reduceToken0Reserves) {
            pool.setDecreaseReserves(true, false);
        }

        if (reduceToken1Reserves) {
            pool.setDecreaseReserves(false, true);
        }

        if (useWrongSelector) {
            return kHYPEWithdrawalModule.convertToToken0.selector;
        } else {
            return IRebalanceModule.rebalance.selector;
        }
    }
}

contract kHYPEWithdrawalModuleTest is Test {
    STEXLens stexLens;

    kHYPEWithdrawalModule _withdrawalModule;

    WETH weth;
    // kHYPE
    ERC20Mock private _token0;

    MockStakingAccountant stakingAccountant;
    MockStakingManager stakingManager;

    MockLendingPool lendingPool;
    AaveLendingModule lendingModule;

    MockRebalanceModule rebalanceModule;

    address private _pool;

    address public owner = makeAddr("OWNER");

    uint256 private constant BIPS = 10_000;

    function setUp() public {
        stexLens = new STEXLens();

        _token0 = new ERC20Mock();
        weth = new WETH();

        stakingAccountant = new MockStakingAccountant(address(_token0));
        stakingManager = new MockStakingManager(address(stakingAccountant), address(_token0));

        // 10 bips unstaking fee
        stakingManager.setUnstakeFeeRate(10);

        _pool = address(new MockPool(address(_token0), address(weth)));

        rebalanceModule = new MockRebalanceModule(weth, MockPool(_pool));

        lendingPool = new MockLendingPool(address(weth));
        assertEq(lendingPool.underlyingAsset(), address(weth));
        assertEq(lendingPool.lendingPoolYieldToken(), address(lendingPool));

        _withdrawalModule = new kHYPEWithdrawalModule(address(stakingAccountant), address(stakingManager), owner);

        vm.startPrank(owner);
        // AMM will be mocked to make testing more flexible
        _withdrawalModule.setSTEX(address(this));
        assertEq(_withdrawalModule.stex(), address(this));
        vm.stopPrank();

        lendingModule = new AaveLendingModule(
            address(lendingPool),
            lendingPool.lendingPoolYieldToken(),
            address(weth),
            address(_withdrawalModule),
            address(0x123),
            2
        );
        assertEq(lendingModule.yieldToken(), lendingPool.lendingPoolYieldToken());
        assertEq(lendingModule.asset(), address(weth));
        assertEq(lendingModule.tokenSweepManager(), address(0x123));
        assertEq(lendingModule.owner(), address(_withdrawalModule));
        assertEq(lendingModule.referralCode(), 2);

        vm.startPrank(owner);
        _withdrawalModule.proposeLendingModule(address(lendingModule), 3 days);
        vm.warp(block.timestamp + 3 days);
        _withdrawalModule.setProposedLendingModule();
        vm.stopPrank();

        assertEq(address(_withdrawalModule.lendingModule()), address(lendingModule));
        assertEq(_withdrawalModule.owner(), owner);

        vm.deal(address(this), 300 ether);
        weth.deposit{value: 100 ether}();

        weth.transfer(address(rebalanceModule), 10 ether);
        assertEq(weth.balanceOf(address(rebalanceModule)), 10 ether);

        stakingManager.stake{value: 100 ether}();
        assertGt(_token0.totalSupply(), 0);
        assertEq(_token0.balanceOf(address(this)), 100 ether);
        assertEq(address(stakingManager).balance, 100 ether);

        _token0.approve(address(_withdrawalModule), 100 ether);
    }

    // AMM mock functions //

    function withdrawalModule() external view returns (address) {
        return address(_withdrawalModule);
    }

    function token0() external view returns (address) {
        return address(_token0);
    }

    function token1() external view returns (address) {
        return address(weth);
    }

    function pool() external view returns (address) {
        return _pool;
    }

    function unstakeToken0Reserves(uint256 _unstakeAmountToken0) external {}

    function supplyToken1Reserves(uint256 amount) external {
        weth.transfer(msg.sender, amount);
    }

    // End of AMM mock functions //

    function testDeploy() public returns (kHYPEWithdrawalModule withdrawalModuleDeployment) {
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__ZeroAddress.selector);
        new kHYPEWithdrawalModule(address(0), address(stakingManager), address(this));

        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__ZeroAddress.selector);
        new kHYPEWithdrawalModule(address(stakingAccountant), address(0), address(this));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new kHYPEWithdrawalModule(address(stakingAccountant), address(stakingManager), address(0));

        withdrawalModuleDeployment =
            new kHYPEWithdrawalModule(address(stakingAccountant), address(stakingManager), address(this));
        assertEq(withdrawalModuleDeployment.stakingAccountant(), address(stakingAccountant));
        assertEq(withdrawalModuleDeployment.stakingManager(), address(stakingManager));
        assertEq(withdrawalModuleDeployment.owner(), address(this));
        assertEq(address(withdrawalModuleDeployment.lendingModule()), address(0));
        assertEq(withdrawalModuleDeployment.amountToken1LendingPool(), 0);
        assertEq(withdrawalModuleDeployment.overseer(), address(stakingManager));
    }

    function testSweep() public {
        ERC20Mock mockToken = new ERC20Mock();
        address recipient = makeAddr("MOCK_RECIPIENT");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.sweep(address(mockToken), recipient);

        vm.startPrank(owner);

        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__ZeroAddress.selector);
        _withdrawalModule.sweep(address(0), recipient);

        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__ZeroAddress.selector);
        _withdrawalModule.sweep(address(mockToken), address(0));

        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__sweep_Token0CannotBeSweeped.selector);
        _withdrawalModule.sweep(address(_token0), recipient);

        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__sweep_Token1CannotBeSweeped.selector);
        _withdrawalModule.sweep(address(weth), recipient);

        mockToken.mint(address(_withdrawalModule), 10 ether);
        _withdrawalModule.sweep(address(mockToken), recipient);
        assertEq(mockToken.balanceOf(recipient), 10 ether);

        vm.stopPrank();
    }

    function testToken0Conversion() public {
        address recipient = makeAddr("MOCK_RECIPIENT");

        uint256 amount0 = 1.1 ether;
        uint256 amount1 = _withdrawalModule.convertToToken1(amount0);
        // Current exchange rate is 1:1
        assertEq(amount0, amount1);
        assertEq(amount0, _withdrawalModule.convertToToken0(amount1));

        // Simulate rewards accrual
        stakingAccountant.setTotalRewards(10 ether);
        amount1 = _withdrawalModule.convertToToken1(amount0);
        // Exchange rate has increased
        assertGt(amount1, amount0);
        assertEq(amount0, _withdrawalModule.convertToToken0(amount1));

        // Simulate slashing
        stakingAccountant.setTotalRewards(0);
        stakingAccountant.setTotalSlashing(10 ether);

        amount1 = _withdrawalModule.convertToToken1(amount0);
        // Exchange rate has decreased
        assertLt(amount1, amount0);
        assertEq(amount0, _withdrawalModule.convertToToken0(amount1));

        uint256 shares = _withdrawalModule.token0BalanceToShares(amount1);
        // token0 balance represents shares of ownership
        assertEq(shares, amount0);
        _token0.transfer(recipient, amount0);

        assertEq(_withdrawalModule.token0SharesOf(recipient), amount0);
        assertEq(_withdrawalModule.token0SharesToBalance(shares), amount1);
    }

    function testStakeAmount1() public {
        assertFalse(_withdrawalModule.isLocked());

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.stakeToken1(1 ether);

        vm.startPrank(owner);

        // Cannot be called when Sovereign Pool is locked, to prevent read-only reentrancy
        MockPool(_pool).setIsLocked(true);
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__PoolNonReentrant.selector);
        _withdrawalModule.stakeToken1(1 ether);
        MockPool(_pool).setIsLocked(false);

        assertEq(_token0.balanceOf(_pool), 0);
        uint256 preToken1Balance = weth.balanceOf(address(this));
        _withdrawalModule.stakeToken1(1 ether);
        assertEq(weth.balanceOf(address(this)), preToken1Balance - 1 ether);
        assertEq(_token0.balanceOf(_pool), _withdrawalModule.convertToToken0(1 ether));

        vm.stopPrank();
    }

    function testAmountToken1LendingPool() public {
        assertFalse(_withdrawalModule.isLocked());

        vm.startPrank(owner);

        uint256 balance = _withdrawalModule.amountToken1LendingPool();
        assertEq(balance, 0);

        _withdrawalModule.supplyToken1ToLendingPool(2 ether);

        balance = _withdrawalModule.amountToken1LendingPool();
        assertEq(balance, 2 ether);

        vm.stopPrank();

        // Simulate yield increase
        weth.transfer(address(lendingPool), 0.1 ether);
        balance = _withdrawalModule.amountToken1LendingPool();
        assertEq(balance, 2.1 ether);
    }

    function testSetSTEX() public {
        kHYPEWithdrawalModule withdrawalModuleDeployment = testDeploy();

        vm.prank(_pool);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _pool));
        withdrawalModuleDeployment.setSTEX(address(this));

        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__ZeroAddress.selector);
        withdrawalModuleDeployment.setSTEX(address(0));

        withdrawalModuleDeployment.setSTEX(address(this));
        assertEq(withdrawalModuleDeployment.stex(), address(this));

        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__setSTEX_AlreadySet.selector);
        withdrawalModuleDeployment.setSTEX(_pool);
    }

    function testReceive() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(_withdrawalModule).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(_withdrawalModule).balance, 1 ether);
    }

    function testBurnToken0AfterWithdraw() public {
        assertFalse(_withdrawalModule.isLocked());

        uint256 amountToken0 = 1 ether;
        address recipient = makeAddr("MOCK_RECIPIENT");

        _burnToken0AfterWithdraw(amountToken0, recipient);
    }

    function testUnstakeToken0Reserves() public {
        assertFalse(_withdrawalModule.isLocked());

        _unstakeToken0Reserves(3 ether);

        // kHYPE amount gets transferred to stakingManager on withdrawals
        assertEq(_token0.balanceOf(address(stakingManager)), 3 ether);
        // withdrawal id has been incremented
        assertEq(stakingManager.nextWithdrawalId(address(_withdrawalModule)), 1);
    }

    function testRebalanceToken0Reserves() public {
        address recipient = makeAddr("MOCK_RECIPIENT");

        assertFalse(_withdrawalModule.isLocked());

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.rebalanceToken0Reserves(1 ether, recipient, address(rebalanceModule), new bytes(0));

        vm.startPrank(owner);

        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__ZeroAddress.selector);
        _withdrawalModule.rebalanceToken0Reserves(1 ether, address(0), address(rebalanceModule), new bytes(0));

        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__rebalanceToken0Reserves_InvalidRecipient.selector);
        _withdrawalModule.rebalanceToken0Reserves(1 ether, recipient, address(rebalanceModule), new bytes(0));

        // Cannot be called when Sovereign Pool is locked, to prevent read-only reentrancy
        MockPool(_pool).setIsLocked(true);
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__PoolNonReentrant.selector);
        _withdrawalModule.rebalanceToken0Reserves(1 ether, recipient, address(rebalanceModule), new bytes(0));
        MockPool(_pool).setIsLocked(false);

        // No state changes
        _withdrawalModule.rebalanceToken0Reserves(0, address(rebalanceModule), address(rebalanceModule), new bytes(0));
        assertEq(weth.balanceOf(_pool), 0);
        assertEq(_token0.balanceOf(_pool), 0);

        vm.stopPrank();

        weth.transfer(_pool, 2 ether);
        _token0.transfer(_pool, 3 ether);
        weth.transfer(owner, 1 ether);

        // Mocks unstaking 1 ether from pool
        _token0.transfer(address(_withdrawalModule), 1 ether);

        vm.startPrank(owner);

        vm.expectRevert(
            kHYPEWithdrawalModule.kHYPEWithdrawalModule__rebalanceToken0Reserves_RebalanceModuleCallFailed.selector
        );
        _withdrawalModule.rebalanceToken0Reserves(
            1 ether, address(rebalanceModule), address(rebalanceModule), abi.encode(true, false, false, false)
        );

        // Call to rebalance module cannot decrease pool reserves

        vm.expectRevert(
            kHYPEWithdrawalModule.kHYPEWithdrawalModule__rebalanceToken0Reserves_PoolToken0ReservesDecreased.selector
        );
        _withdrawalModule.rebalanceToken0Reserves(
            1 ether, address(rebalanceModule), address(rebalanceModule), abi.encode(false, true, false, false)
        );

        vm.expectRevert(
            kHYPEWithdrawalModule.kHYPEWithdrawalModule__rebalanceToken0Reserves_PoolToken1ReservesDecreased.selector
        );
        _withdrawalModule.rebalanceToken0Reserves(
            1 ether, address(rebalanceModule), address(rebalanceModule), abi.encode(false, false, true, false)
        );

        vm.expectRevert(
            kHYPEWithdrawalModule.kHYPEWithdrawalModule__rebalanceToken0Reserves_InsufficientToken1Received.selector
        );
        _withdrawalModule.rebalanceToken0Reserves(
            1 ether, address(rebalanceModule), address(rebalanceModule), abi.encode(false, false, false, true)
        );

        uint256 snapshot = vm.snapshotState();

        _withdrawalModule.rebalanceToken0Reserves(
            1 ether, address(rebalanceModule), address(rebalanceModule), abi.encode(false, false, false, false)
        );

        assertEq(weth.balanceOf(_pool), 2 ether + (1 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS);
        assertEq(_token0.balanceOf(address(rebalanceModule)), 1 ether);
        assertEq(_token0.balanceOf(recipient), 0);

        vm.revertToState(snapshot);

        weth.approve(address(_withdrawalModule), (1 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS);
        _withdrawalModule.rebalanceToken0Reserves(
            1 ether,
            recipient,
            address(0), // Assumes that this contract will transfer token1 amount
            abi.encode(false, false, false, false)
        );

        assertEq(weth.balanceOf(_pool), 2 ether + (1 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS);
        assertEq(_token0.balanceOf(recipient), 1 ether);

        vm.stopPrank();
    }

    function testUnstakeExcessToken0() public {
        assertFalse(_withdrawalModule.isLocked());

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.unstakeExcessToken0();

        vm.startPrank(owner);

        uint256 preBalance = _token0.balanceOf(address(stakingManager));
        _withdrawalModule.unstakeExcessToken0();
        uint256 postBalance = _token0.balanceOf(address(stakingManager));
        assertEq(preBalance, postBalance);

        vm.stopPrank();

        _unstakeToken0Reserves(10 ether);
        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(),
            (10 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS
        );
        assertEq(stakingManager.nextWithdrawalId(address(_withdrawalModule)), 1);
        // Simulates cancellation of token0 withdrawal,
        // which returns original token0 amount back to withdrawal module
        stakingManager.cancelWithdrawal(address(_withdrawalModule), 0);
        assertEq(_token0.balanceOf(address(_withdrawalModule)), 10 ether);

        vm.startPrank(owner);

        _withdrawalModule.unstakeExcessToken0();
        postBalance = _token0.balanceOf(address(stakingManager));
        assertEq(postBalance - preBalance, 10 ether);
        // A new withdrawal request has been created
        assertEq(stakingManager.nextWithdrawalId(address(_withdrawalModule)), 2);
        // token0 amount pending unstaking does not get updated,
        // since the token0 balance is the result of a cancelled withdrawal
        // which was already unstaked and accounted for
        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(),
            (10 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS
        );
        assertEq(
            _withdrawalModule.amountToken0PendingUnstakingBeforeUpdate(),
            (10 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS
        );

        bool isConfirmed = _withdrawalModule.confirmWithdrawal(0);
        // First withdrawal request has been cancelled
        assertFalse(isConfirmed);

        vm.deal(address(stakingManager), (10 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS);
        vm.warp(block.timestamp + 7 days);

        // Second withdrawal request has been processed
        isConfirmed = _withdrawalModule.confirmWithdrawal(1);
        assertTrue(isConfirmed);
        // update has been called
        assertEq(_withdrawalModule.amountToken0PendingUnstaking(), 0);
        assertEq(_withdrawalModule.amountToken0PendingUnstakingBeforeUpdate(), 0);
        assertEq(_withdrawalModule.amountToken1ClaimableLPWithdrawal(), 0);
        assertEq(weth.balanceOf(_pool), (10 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS);

        vm.stopPrank();

        _withdrawalModule.update();
        // update has already been called,
        // hence no state changes
        assertEq(_withdrawalModule.amountToken0PendingUnstakingBeforeUpdate(), 0);
        assertEq(_withdrawalModule.amountToken0PendingUnstaking(), 0);
        assertEq(weth.balanceOf(_pool), (10 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS);
        assertEq(_withdrawalModule.amountToken1ClaimableLPWithdrawal(), 0);
    }

    function testWithdrawToken1FromLendingPool() public {
        assertFalse(_withdrawalModule.isLocked());

        uint256 amountToken1 = 1 ether;
        address recipient = makeAddr("MOCK_RECIPIENT");

        vm.prank(recipient);
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__OnlySTEXOrOwner.selector);
        _withdrawalModule.withdrawToken1FromLendingPool(amountToken1, recipient);

        vm.startPrank(owner);

        // Owner transfers liquidity from lending pool to sovereign pool
        _withdrawalModule.supplyToken1ToLendingPool(2 * amountToken1);

        // Cannot be called when Sovereign Pool is locked, to prevent read-only reentrancy
        MockPool(_pool).setIsLocked(true);
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__PoolNonReentrant.selector);
        _withdrawalModule.withdrawToken1FromLendingPool(amountToken1, recipient);
        MockPool(_pool).setIsLocked(false);

        _withdrawalModule.withdrawToken1FromLendingPool(amountToken1, recipient);
        assertEq(weth.balanceOf(_pool), amountToken1);
        assertEq(weth.balanceOf(recipient), 0);

        vm.stopPrank();

        uint256 snapshot = vm.snapshotState();

        // AMM transfers liquidity from lending pool to recipient
        _withdrawalModule.withdrawToken1FromLendingPool(amountToken1, recipient);
        assertEq(weth.balanceOf(recipient), amountToken1);

        vm.revertToState(snapshot);

        // Revert happens if recipient receives less than amountToken1
        lendingPool.setIsCompromised(true);

        vm.expectRevert(
            kHYPEWithdrawalModule
                .kHYPEWithdrawalModule__withdrawToken1FromLendingPool_InsufficientAmountWithdrawn
                .selector
        );
        _withdrawalModule.withdrawToken1FromLendingPool(amountToken1, recipient);
    }

    function testConfirmWithdrawal() public {
        _unstakeToken0Reserves(3 ether);
        _unstakeToken0Reserves(7 ether);

        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(),
            (10 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS
        );

        // kHYPE amount gets transferred to stakingManager on withdrawals
        assertEq(_token0.balanceOf(address(stakingManager)), 10 ether);
        // withdrawal id has been incremented
        assertEq(stakingManager.nextWithdrawalId(address(_withdrawalModule)), 2);

        // Cannot be called when Sovereign Pool is locked, to prevent read-only reentrancy
        MockPool(_pool).setIsLocked(true);
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__PoolNonReentrant.selector);
        _withdrawalModule.confirmWithdrawal(0);
        MockPool(_pool).setIsLocked(false);

        bool isConfirmed = _withdrawalModule.confirmWithdrawal(0);
        assertFalse(isConfirmed);
        isConfirmed = _withdrawalModule.confirmWithdrawal(1);
        assertFalse(isConfirmed);

        vm.deal(address(stakingManager), (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS);

        vm.warp(block.timestamp + 7 days);

        isConfirmed = _withdrawalModule.confirmWithdrawal(0);
        assertTrue(isConfirmed);
        vm.expectRevert(bytes("Insufficient contract balance"));
        _withdrawalModule.confirmWithdrawal(1);

        vm.deal(address(stakingManager), (7 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS);
        isConfirmed = _withdrawalModule.confirmWithdrawal(1);
        assertTrue(isConfirmed);

        // kHYPE fee was transferred to treasury
        assertGt(_token0.balanceOf(stakingManager.TREASURY()), 0);
        // withdrawal module received correct amount of token1,
        // and update has been called
        assertEq(address(_withdrawalModule).balance, 0);
        assertEq(weth.balanceOf(address(_withdrawalModule)), 0);
        assertEq(weth.balanceOf(address(_pool)), (10 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS);
        assertEq(_withdrawalModule.amountToken0PendingUnstaking(), 0);
        // No LP withdrawals to process
        assertEq(_withdrawalModule.amountToken1ClaimableLPWithdrawal(), 0);

        // Withdrawals have already been confirmed
        isConfirmed = _withdrawalModule.confirmWithdrawal(0);
        assertFalse(isConfirmed);
        isConfirmed = _withdrawalModule.confirmWithdrawal(1);
        assertFalse(isConfirmed);
    }

    function testSettlePendingWithdrawalsWithPoolReserves() public {
        assertFalse(_withdrawalModule.isLocked());

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.settlePendingWithdrawalsWithPoolReserves(1 ether);

        vm.startPrank(owner);

        // No state updates have happened
        _withdrawalModule.settlePendingWithdrawalsWithPoolReserves(0);
        assertEq(_withdrawalModule.amountToken1ClaimableLPWithdrawal(), 0);
        assertEq(address(_withdrawalModule).balance, 0);
        assertEq(_withdrawalModule.amountToken0PendingUnstaking(), 0);

        // Cannot be called when Sovereign Pool is locked, to prevent read-only reentrancy
        MockPool(_pool).setIsLocked(true);
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__PoolNonReentrant.selector);
        _withdrawalModule.settlePendingWithdrawalsWithPoolReserves(1 ether);
        MockPool(_pool).setIsLocked(false);

        vm.stopPrank();

        _unstakeToken0Reserves(3 ether);

        assertEq(address(_withdrawalModule).balance, 0);
        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(),
            (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS
        );
        assertEq(_withdrawalModule.amountToken1PendingLPWithdrawal(), 0);
        assertEq(_withdrawalModule.amountToken1ClaimableLPWithdrawal(), 0);

        address recipient = makeAddr("MOCK_RECIPIENT");

        _burnToken0AfterWithdraw(3 ether, recipient);

        // Simulate partial unstaking of 1e18 native token
        vm.deal(address(_withdrawalModule), 1 ether);

        assertEq(address(_withdrawalModule).balance, 1 ether);
        assertEq(
            _withdrawalModule.amountToken1PendingLPWithdrawal(),
            (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS - 1 ether
        );
        assertEq(
            _withdrawalModule.amountToken1PendingLPWithdrawalBeforeUpdate(),
            (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS
        );
        // 1e18 of native token has reduced the amount of token0 pending unstaking proportionally
        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(),
            (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS - 1 ether
        );
        assertEq(
            _withdrawalModule.amountToken0PendingUnstakingBeforeUpdate(),
            (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS
        );

        vm.startPrank(owner);

        _withdrawalModule.settlePendingWithdrawalsWithPoolReserves(3 ether);

        assertEq(address(_withdrawalModule).balance, (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS);
        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(),
            (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS - 1 ether
        );
        // update has been called at least once
        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(),
            _withdrawalModule.amountToken0PendingUnstakingBeforeUpdate()
        );
        assertEq(
            _withdrawalModule.amountToken1PendingLPWithdrawal(),
            _withdrawalModule.amountToken1PendingLPWithdrawalBeforeUpdate()
        );
        // LP withdrawal is fully claimable,
        // since sufficient native token has been supplied from the pool
        assertEq(_withdrawalModule.amountToken1PendingLPWithdrawal(), 0);
        assertEq(
            _withdrawalModule.amountToken1ClaimableLPWithdrawal(),
            (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS
        );

        // Left-over token1 amount got sent back to pool
        assertEq(weth.balanceOf(_pool), (3 ether * stakingManager.unstakeFeeRate()) / BIPS + 1 ether);

        // recipient is able to claim
        _withdrawalModule.claim(0);
        assertEq(recipient.balance, (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS);

        vm.stopPrank();
    }

    function testUpdate() public {
        assertFalse(_withdrawalModule.isLocked());

        // No state updates have happened
        _withdrawalModule.update();
        assertEq(_withdrawalModule.amountToken1ClaimableLPWithdrawal(), 0);
        assertEq(address(_withdrawalModule).balance, 0);
        assertEq(_withdrawalModule.amountToken0PendingUnstaking(), 0);
        assertEq(_withdrawalModule.cumulativeAmountToken1ClaimableLPWithdrawal(), 0);

        // Cannot be called when Sovereign Pool is locked, to prevent read-only reentrancy
        MockPool(_pool).setIsLocked(true);
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__PoolNonReentrant.selector);
        _withdrawalModule.update();
        MockPool(_pool).setIsLocked(false);

        _unstakeToken0Reserves(3 ether);

        assertEq(address(_withdrawalModule).balance, 0);
        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(),
            (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS
        );

        uint256 snapshot = vm.snapshotState();
        uint256 snapshot2 = vm.snapshotState();

        // Scenario 1: update with partial unstaking fulfilled
        vm.deal(address(_withdrawalModule), 2 ether);
        _withdrawalModule.update();

        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(),
            (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS - _withdrawalModule.convertToToken0(2 ether)
        );
        // All native token got wrapped and transferred into pool,
        // since there were no LP withdrawals to fulfill
        assertEq(address(_withdrawalModule).balance, 0);
        assertEq(weth.balanceOf(_pool), 2 ether);

        vm.revertToState(snapshot2);

        // Scenario 2: update with partial unstaking fulfilled and partial LP withdrawal

        address recipient = makeAddr("MOCK_RECIPIENT");
        _withdrawalModule.burnToken0AfterWithdraw(1 ether, recipient);
        uint256 amountToken1PendingLPWithdrawal = _withdrawalModule.amountToken1PendingLPWithdrawal();
        assertEq(
            amountToken1PendingLPWithdrawal,
            _withdrawalModule.convertToToken1((1 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS)
        );

        vm.deal(address(_withdrawalModule), 0.5 ether);
        assertEq(
            _withdrawalModule.amountToken0PendingUnstakingBeforeUpdate(),
            (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS
        );
        assertEq(
            _withdrawalModule.amountToken1PendingLPWithdrawalBeforeUpdate(),
            (1 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS
        );
        _withdrawalModule.update();

        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(),
            (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS - _withdrawalModule.convertToToken0(0.5 ether)
        );
        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(),
            _withdrawalModule.amountToken0PendingUnstakingBeforeUpdate()
        );
        assertEq(_withdrawalModule.amountToken1ClaimableLPWithdrawal(), 0.5 ether);
        assertEq(_withdrawalModule.amountToken1PendingLPWithdrawal(), amountToken1PendingLPWithdrawal - 0.5 ether);
        assertEq(
            _withdrawalModule.amountToken1PendingLPWithdrawal(),
            _withdrawalModule.amountToken1PendingLPWithdrawalBeforeUpdate()
        );
        assertEq(address(_withdrawalModule).balance, 0.5 ether);
        // Not enough native token left to re-deposit into pool
        assertEq(weth.balanceOf(_pool), 0);

        // Cannot claim withdrawal request because there is not enough native token available
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__claim_InsufficientAmountToClaim.selector);
        _withdrawalModule.claim(0);

        vm.revertToState(snapshot);

        // Scenario 3: Update with all unstaking requests and LP withdrawals fulfilled
        // + remaining funds re-deposited into pool

        recipient = makeAddr("MOCK_RECIPIENT");

        _withdrawalModule.burnToken0AfterWithdraw(1 ether, recipient);

        amountToken1PendingLPWithdrawal = _withdrawalModule.amountToken1PendingLPWithdrawal();
        assertEq(
            amountToken1PendingLPWithdrawal,
            _withdrawalModule.convertToToken1((1 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS)
        );

        bool isConfirmed = _withdrawalModule.confirmWithdrawal(0);
        assertFalse(isConfirmed);

        vm.warp(block.timestamp + 7 days);

        isConfirmed = _withdrawalModule.confirmWithdrawal(0);
        assertTrue(isConfirmed);
        assertEq(_withdrawalModule.amountToken0PendingUnstaking(), 0);

        _withdrawalModule.update();

        // All unstaking requests got fulfilled
        assertEq(_withdrawalModule.amountToken0PendingUnstaking(), 0);
        // Pending LP withdrawal can now be claimed
        assertEq(_withdrawalModule.amountToken1ClaimableLPWithdrawal(), amountToken1PendingLPWithdrawal);
        assertEq(_withdrawalModule.amountToken1PendingLPWithdrawal(), 0);
        assertEq(address(_withdrawalModule).balance, amountToken1PendingLPWithdrawal);
        // Remaining native token amount got wrapped and re-deposited into pool
        assertEq(
            weth.balanceOf(_pool),
            (3 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS - amountToken1PendingLPWithdrawal
        );

        _withdrawalModule.claim(0);
        assertEq(recipient.balance, amountToken1PendingLPWithdrawal);
    }

    function testClaim__WithPriority() public {
        assertFalse(_withdrawalModule.isLocked());

        uint256 amount1 = 1 ether;
        address recipient1 = makeAddr("MOCK_RECIPIENT_1");
        // User 1 requests withdrawal (before unstaking fulfillment)
        _burnToken0AfterWithdraw(amount1, recipient1);
        LPWithdrawalRequest memory request1 = _withdrawalModule.getLPWithdrawals(0);
        assertEq(request1.recipient, recipient1);
        assertEq(
            request1.amountToken1,
            _withdrawalModule.convertToToken1((amount1 * (BIPS - stakingManager.unstakeFeeRate())) / BIPS)
        );
        assertEq(request1.cumulativeAmountToken1LPWithdrawalCheckpoint, 0);
        assertEq(_withdrawalModule.cumulativeAmountToken1LPWithdrawal(), request1.amountToken1);
        assertEq(_withdrawalModule.cumulativeAmountToken1ClaimableLPWithdrawal(), 0);

        // User 2 requests withdrawal (before unstaking fulfillment)
        uint256 amount2 = 2 ether;
        address recipient2 = makeAddr("MOCK_RECIPIENT_2");
        _burnToken0AfterWithdraw(amount2, recipient2);
        LPWithdrawalRequest memory request2 = _withdrawalModule.getLPWithdrawals(1);
        assertEq(request2.recipient, recipient2);
        assertEq(
            request2.amountToken1,
            _withdrawalModule.convertToToken1((amount2 * (BIPS - stakingManager.unstakeFeeRate())) / BIPS)
        );
        assertEq(request2.cumulativeAmountToken1LPWithdrawalCheckpoint, request1.amountToken1);
        assertEq(_withdrawalModule.cumulativeAmountToken1LPWithdrawal(), request1.amountToken1 + request2.amountToken1);
        assertEq(_withdrawalModule.cumulativeAmountToken1ClaimableLPWithdrawal(), 0);

        // Simulate unstaking fulfillment
        vm.deal(address(_withdrawalModule), 4 ether);
        _withdrawalModule.update();
        assertEq(_withdrawalModule.amountToken1ClaimableLPWithdrawal(), request1.amountToken1 + request2.amountToken1);
        assertEq(_withdrawalModule.cumulativeAmountToken1LPWithdrawal(), request1.amountToken1 + request2.amountToken1);

        // Surplus wrapped native token was transferred to pool
        assertEq(weth.balanceOf(address(_pool)), 4 ether - request1.amountToken1 - request2.amountToken1);

        // User 3 requests withdrawal (after unstaking fulfillment)
        uint256 amount3 = 0.1 ether;
        address recipient3 = makeAddr("MOCK_RECIPIENT_3");
        _burnToken0AfterWithdraw(amount3, recipient3);
        LPWithdrawalRequest memory request3 = _withdrawalModule.getLPWithdrawals(2);
        assertEq(request3.recipient, recipient3);
        assertEq(
            request3.amountToken1,
            _withdrawalModule.convertToToken1((amount3 * (BIPS - stakingManager.unstakeFeeRate())) / BIPS)
        );
        assertEq(request3.cumulativeAmountToken1LPWithdrawalCheckpoint, request1.amountToken1 + request2.amountToken1);

        // User 1 can claim, because it requested withdrawal before the call to `update`
        assertTrue(stexLens.canClaim(address(this), 0));
        _withdrawalModule.claim(0);
        assertEq(recipient1.balance, request1.amountToken1);
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__claim_AlreadyClaimed.selector);
        _withdrawalModule.claim(0);

        // User 3 cannot claim, because it requested withdrawal after the call to `update`
        assertFalse(stexLens.canClaim(address(this), 2));
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__claim_CannotYetClaim.selector);
        _withdrawalModule.claim(2);

        // User 2 can claim, similar scenario to user 1
        assertTrue(stexLens.canClaim(address(this), 1));
        _withdrawalModule.claim(1);
        assertEq(recipient2.balance, request2.amountToken1);

        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__claim_AlreadyClaimed.selector);
        _withdrawalModule.claim(1);

        // User 3 still cannot claim, also because there is not enough ETH
        assertFalse(stexLens.canClaim(address(this), 2));

        // Simulate unstaking fulfillment
        vm.deal(address(_withdrawalModule), 0.1 ether);
        _withdrawalModule.update();

        // User 3 can now claim
        assertTrue(stexLens.canClaim(address(this), 2));
        _withdrawalModule.claim(2);
        assertEq(recipient3.balance, request3.amountToken1);

        // User 3 already claimed
        assertFalse(stexLens.canClaim(address(this), 2));
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__claim_AlreadyClaimed.selector);
        _withdrawalModule.claim(2);
    }

    function testClaim__WithPriority__LaterWithdrawalsCannotJumpQueuePriority() public {
        address recipient1 = makeAddr("RECIPIENT_1");
        address recipient2 = makeAddr("RECIPIENT_2");

        // user 1 creates a withdraw request
        _burnToken0AfterWithdraw(10e18, recipient1);

        // Simulate partial unstaking via `overseer`
        vm.deal(address(_withdrawalModule), 5 ether);
        _withdrawalModule.update();

        // user2 creates a smaller withdraw request
        _burnToken0AfterWithdraw(1e18, recipient2);

        // More native token gets unstaked, but not enough to fulfill both requests
        vm.deal(address(_withdrawalModule), (10 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS);
        _withdrawalModule.update();

        // user2 tries to claim, but cannot because of queue priority
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__claim_CannotYetClaim.selector);
        _withdrawalModule.claim(1);

        // user1 can claim
        _withdrawalModule.claim(0);
        assertEq(
            recipient1.balance,
            _withdrawalModule.convertToToken1((10 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS)
        );
        assertEq(address(_withdrawalModule).balance, 0);

        // More native token gets unstaked via `overseer`
        vm.deal(address(_withdrawalModule), (1 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS);
        _withdrawalModule.update();

        // user2 can now claim
        _withdrawalModule.claim(1);
        assertEq(
            recipient2.balance,
            _withdrawalModule.convertToToken1((1 ether * (BIPS - stakingManager.unstakeFeeRate())) / BIPS)
        );
    }

    function testLendingModuleProposal() public {
        assertEq(address(_withdrawalModule.lendingModule()), address(lendingModule));

        // Deposit some wrapped native token into lending module
        vm.startPrank(owner);

        uint256 amount = 2 ether;
        _withdrawalModule.supplyToken1ToLendingPool(2 ether);
        assertEq(lendingModule.assetBalance(), 2 ether);

        vm.stopPrank();

        address lendingModuleMock = address(
            new AaveLendingModule(
                address(lendingPool),
                lendingPool.lendingPoolYieldToken(),
                address(weth),
                address(_withdrawalModule),
                address(0x123),
                2
            )
        );

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.proposeLendingModule(lendingModuleMock, 3 days);

        vm.startPrank(owner);

        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule___verifyTimelockDelay_TimelockTooLow.selector);
        _withdrawalModule.proposeLendingModule(lendingModuleMock, 3 days - 1);
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule___verifyTimelockDelay_TimelockTooHigh.selector);
        _withdrawalModule.proposeLendingModule(lendingModuleMock, 7 days + 1);

        _withdrawalModule.proposeLendingModule(lendingModuleMock, 3 days);
        (address lendingModuleProposed, uint256 startTimestamp) = _withdrawalModule.lendingModuleProposal();
        assertEq(lendingModuleProposed, lendingModuleMock);
        assertEq(startTimestamp, block.timestamp + 3 days);

        vm.expectRevert(
            kHYPEWithdrawalModule.kHYPEWithdrawalModule__proposeLendingModule_ProposalAlreadyActive.selector
        );
        _withdrawalModule.proposeLendingModule(lendingModuleMock, 3 days);

        vm.stopPrank();

        uint256 snapshot = vm.snapshotState();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.cancelLendingModuleProposal();

        vm.startPrank(owner);

        _withdrawalModule.cancelLendingModuleProposal();
        (lendingModuleProposed, startTimestamp) = _withdrawalModule.lendingModuleProposal();
        assertEq(lendingModuleProposed, address(0));
        assertEq(startTimestamp, 0);

        vm.stopPrank();

        vm.revertToState(snapshot);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.setProposedLendingModule();

        vm.startPrank(owner);

        // Cannot be called when Sovereign Pool is locked, to prevent read-only reentrancy
        MockPool(_pool).setIsLocked(true);
        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__PoolNonReentrant.selector);
        _withdrawalModule.setProposedLendingModule();
        MockPool(_pool).setIsLocked(false);

        vm.expectRevert(
            kHYPEWithdrawalModule.kHYPEWithdrawalModule__setProposedLendingModule_ProposalNotActive.selector
        );
        _withdrawalModule.setProposedLendingModule();

        vm.warp(block.timestamp + 3 days);

        uint256 preBalancePool = weth.balanceOf(address(_pool));
        _withdrawalModule.setProposedLendingModule();
        assertEq(address(_withdrawalModule.lendingModule()), lendingModuleMock);
        // Old lending module's asset (wrapped native) balance is now 0,
        // all of it has been transferred to `_pool`
        uint256 postBalancePool = weth.balanceOf(address(_pool));
        assertEq(lendingModule.assetBalance(), 0);
        assertEq(postBalancePool - preBalancePool, amount);

        (lendingModuleProposed, startTimestamp) = _withdrawalModule.lendingModuleProposal();
        assertEq(lendingModuleProposed, address(0));
        assertEq(startTimestamp, 0);

        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__setProposedLendingModule_InactiveProposal.selector);
        _withdrawalModule.setProposedLendingModule();

        vm.stopPrank();
    }

    function _burnToken0AfterWithdraw(uint256 amountToken0, address recipient) private {
        vm.prank(_pool);

        vm.expectRevert(kHYPEWithdrawalModule.kHYPEWithdrawalModule__OnlySTEX.selector);
        _withdrawalModule.burnToken0AfterWithdraw(amountToken0, recipient);

        uint256 preAmountToken0PendingUnstaking = _withdrawalModule.amountToken0PendingUnstaking();
        uint256 preAmountToken1PendingLPWithdrawal = _withdrawalModule.amountToken1PendingLPWithdrawal();
        uint256 preAmountCumulative = _withdrawalModule.cumulativeAmountToken1LPWithdrawal();

        _withdrawalModule.burnToken0AfterWithdraw(amountToken0, recipient);
        // No token0 has been unstaked
        assertEq(_withdrawalModule.amountToken0PendingUnstaking(), preAmountToken0PendingUnstaking);
        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(),
            _withdrawalModule.amountToken0PendingUnstakingBeforeUpdate()
        );
        assertEq(
            _withdrawalModule.amountToken1PendingLPWithdrawal(),
            _withdrawalModule.convertToToken1((amountToken0 * (BIPS - stakingManager.unstakeFeeRate())) / BIPS)
                + preAmountToken1PendingLPWithdrawal
        );
        assertEq(
            _withdrawalModule.amountToken1PendingLPWithdrawal(),
            _withdrawalModule.amountToken1PendingLPWithdrawalBeforeUpdate()
        );

        uint256 preId = _withdrawalModule.idLPWithdrawal() - 1;
        {
            LPWithdrawalRequest memory request = _withdrawalModule.getLPWithdrawals(preId);
            assertEq(request.recipient, recipient);
            assertEq(
                request.amountToken1,
                _withdrawalModule.convertToToken1((amountToken0 * (BIPS - stakingManager.unstakeFeeRate())) / BIPS)
            );
            assertEq(request.cumulativeAmountToken1LPWithdrawalCheckpoint, preAmountCumulative);
        }
    }

    function _unstakeToken0Reserves(uint256 amount) private {
        uint256 initialToken0Reserves = _token0.balanceOf(address(this));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _withdrawalModule.unstakeToken0Reserves(initialToken0Reserves);

        uint256 preAmountToken0PendingUnstaking = _withdrawalModule.amountToken0PendingUnstaking();
        _token0.transfer(address(_withdrawalModule), amount);

        vm.startPrank(owner);

        _withdrawalModule.unstakeToken0Reserves(amount);

        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(),
            preAmountToken0PendingUnstaking + (amount * (BIPS - stakingManager.unstakeFeeRate())) / BIPS
        );
        assertEq(
            _withdrawalModule.amountToken0PendingUnstaking(),
            _withdrawalModule.amountToken0PendingUnstakingBeforeUpdate()
        );

        vm.stopPrank();
    }
}
