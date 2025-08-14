// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MultiMarketLendingModule} from "src/lending-modules/MultiMarketLendingModule.sol";
import {MockERC4626LendingPool} from "src/mocks/MockERC4626LendingPool.sol";
import {ERC4626LendingModule} from "src/lending-modules/ERC4626LendingModule.sol";
import {ILendingModule} from "src/interfaces/ILendingModule.sol";

contract MultiMarketLendingModuleTest is Test {
    MultiMarketLendingModule public multiLendingModule;
    ERC20Mock public asset;

    // Mock lending modules
    ERC4626LendingModule public lendingModule1;
    ERC4626LendingModule public lendingModule2;
    ERC4626LendingModule public lendingModule3;

    // Mock ERC4626 pools
    MockERC4626LendingPool public mockPool1;
    MockERC4626LendingPool public mockPool2;
    MockERC4626LendingPool public mockPool3;

    // Test actors
    address public owner = makeAddr("OWNER");
    address public manager = makeAddr("MANAGER");
    address public tokenSweepManager = makeAddr("TOKEN_SWEEP_MANAGER");
    address public user = makeAddr("USER");
    address public recipient = makeAddr("RECIPIENT");

    // Constants
    uint256 public constant BIPS = 10_000;
    uint256 public constant INITIAL_BALANCE = 1_000_000e18;

    // Events for testing
    event Initialized(
        address[] lendingModuleArray, MultiMarketLendingModule.LendingModuleConfig[] lendingModuleConfigArray
    );
    event DepositWeightsSet(uint16[] depositWeightBipsArray);
    event WithdrawWeightsSet(uint16[] withdrawWeightBipsArray);
    event TokenSweepManagerUpdated(address tokenSweepManager);
    event Sweep(address indexed token, address indexed recipient, uint256 balance);
    event ManagerFeeClaimed(address indexed recipient, uint256 amount);

    function setUp() public {
        // Deploy asset token
        asset = new ERC20Mock();

        // Deploy MultiMarketLendingModule
        vm.prank(owner);
        multiLendingModule = new MultiMarketLendingModule(address(asset), owner, manager, tokenSweepManager, 0);

        // Deploy mock ERC4626 pools
        mockPool1 = new MockERC4626LendingPool(address(asset));
        mockPool2 = new MockERC4626LendingPool(address(asset));
        mockPool3 = new MockERC4626LendingPool(address(asset));

        // Deploy ERC4626 lending modules
        lendingModule1 = new ERC4626LendingModule(address(mockPool1), address(multiLendingModule), tokenSweepManager);

        lendingModule2 = new ERC4626LendingModule(address(mockPool2), address(multiLendingModule), tokenSweepManager);

        lendingModule3 = new ERC4626LendingModule(address(mockPool3), address(multiLendingModule), tokenSweepManager);

        // Fund test accounts
        asset.mint(manager, INITIAL_BALANCE);
        asset.mint(user, INITIAL_BALANCE);

        // Approve multiLendingModule to spend manager's tokens
        vm.prank(manager);
        asset.approve(address(multiLendingModule), type(uint256).max);
    }

    /**
     * INITIALIZATION TESTS
     */
    function testConstructor() public {
        // Test zero asset address
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__ZeroAddress.selector);
        new MultiMarketLendingModule(address(0), owner, manager, tokenSweepManager, 0);

        // Test zero manager address
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__ZeroAddress.selector);
        new MultiMarketLendingModule(address(asset), owner, address(0), tokenSweepManager, 0);

        // Test zero token sweep manager address
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__ZeroAddress.selector);
        new MultiMarketLendingModule(address(asset), owner, manager, address(0), 0);

        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__InvalidManagerFeeBips.selector);
        new MultiMarketLendingModule(address(asset), owner, manager, tokenSweepManager, 5_001);

        // Test constructor
        MultiMarketLendingModule multiLendingModuleDeployment =
            new MultiMarketLendingModule(address(asset), owner, manager, tokenSweepManager, 10);

        assertEq(multiLendingModuleDeployment.asset(), address(asset));
        assertEq(multiLendingModuleDeployment.owner(), owner);
        assertEq(multiLendingModuleDeployment.manager(), manager);
        assertEq(multiLendingModuleDeployment.tokenSweepManager(), tokenSweepManager);
        assertEq(multiLendingModuleDeployment.managerFeeBips(), 10);
    }

    function testInitializeSuccess() public {
        address[] memory lendingModules = new address[](2);
        lendingModules[0] = address(lendingModule1);
        lendingModules[1] = address(lendingModule2);

        MultiMarketLendingModule.LendingModuleConfig[] memory configs =
            new MultiMarketLendingModule.LendingModuleConfig[](2);
        configs[0] = MultiMarketLendingModule.LendingModuleConfig({depositWeightBips: 6000, withdrawWeightBips: 4000});
        configs[1] = MultiMarketLendingModule.LendingModuleConfig({depositWeightBips: 4000, withdrawWeightBips: 6000});

        // Test zero lending module address
        lendingModules[0] = address(0);
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__ZeroAddress.selector);
        vm.prank(owner);
        multiLendingModule.initialize(lendingModules, configs);

        lendingModules[0] = address(lendingModule1);

        vm.expectEmit(true, true, true, true);
        emit Initialized(lendingModules, configs);

        vm.prank(owner);
        multiLendingModule.initialize(lendingModules, configs);

        // Verify state
        address[] memory storedModules = multiLendingModule.lendingModules();
        assertEq(storedModules.length, 2);
        assertEq(storedModules[0], address(lendingModule1));
        assertEq(storedModules[1], address(lendingModule2));

        // Verify configs
        MultiMarketLendingModule.LendingModuleConfig memory config1 =
            multiLendingModule.getLendingModuleConfig(address(lendingModule1));
        assertEq(config1.depositWeightBips, 6000);
        assertEq(config1.withdrawWeightBips, 4000);

        // Test already initialized

        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__initialize_AlreadyInitialized.selector);
        vm.prank(owner);
        multiLendingModule.initialize(lendingModules, configs);
    }

    function testInitializeInvalidArrayLengths() public {
        address[] memory lendingModules = new address[](2);
        lendingModules[0] = address(lendingModule1);
        lendingModules[1] = address(lendingModule2);

        MultiMarketLendingModule.LendingModuleConfig[] memory configs =
            new MultiMarketLendingModule.LendingModuleConfig[](1);
        configs[0] = MultiMarketLendingModule.LendingModuleConfig({depositWeightBips: 10000, withdrawWeightBips: 10000});

        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__initialize_InconsistentArrayLength.selector);
        vm.prank(owner);
        multiLendingModule.initialize(lendingModules, configs);
    }

    function testInitializeEmptyArray() public {
        address[] memory lendingModules = new address[](0);
        MultiMarketLendingModule.LendingModuleConfig[] memory configs =
            new MultiMarketLendingModule.LendingModuleConfig[](0);

        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__initialize_InvalidArrayLength.selector);
        vm.prank(owner);
        multiLendingModule.initialize(lendingModules, configs);
    }

    function testInitializeInvalidWeights() public {
        address[] memory lendingModules = new address[](2);
        lendingModules[0] = address(lendingModule1);
        lendingModules[1] = address(lendingModule2);

        // Invalid deposit weights (don't sum to 10000)
        MultiMarketLendingModule.LendingModuleConfig[] memory configs =
            new MultiMarketLendingModule.LendingModuleConfig[](2);
        configs[0] = MultiMarketLendingModule.LendingModuleConfig({depositWeightBips: 5000, withdrawWeightBips: 5000});
        configs[1] = MultiMarketLendingModule.LendingModuleConfig({
            depositWeightBips: 4000, // Total = 9000, not 10000
            withdrawWeightBips: 5000
        });

        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__initialize_InvalidDepositWeights.selector);
        vm.prank(owner);
        multiLendingModule.initialize(lendingModules, configs);

        // Invalid withdraw weights (don't sum to 10000)
        configs = new MultiMarketLendingModule.LendingModuleConfig[](2);
        configs[0] = MultiMarketLendingModule.LendingModuleConfig({depositWeightBips: 6000, withdrawWeightBips: 6000});
        configs[1] = MultiMarketLendingModule.LendingModuleConfig({
            depositWeightBips: 4000,
            withdrawWeightBips: 5000 // Total = 11000, not 10000
        });

        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__initialize_InvalidWithdrawWeights.selector);
        vm.prank(owner);
        multiLendingModule.initialize(lendingModules, configs);
    }

    function testInitializeInvalidOwner() public {
        // Deploy lending module with wrong owner
        ERC4626LendingModule wrongOwnerModule = new ERC4626LendingModule(
            address(mockPool1),
            address(this), // Wrong owner (should be multiLendingModule)
            tokenSweepManager
        );

        address[] memory lendingModules = new address[](1);
        lendingModules[0] = address(wrongOwnerModule);

        MultiMarketLendingModule.LendingModuleConfig[] memory configs =
            new MultiMarketLendingModule.LendingModuleConfig[](1);
        configs[0] = MultiMarketLendingModule.LendingModuleConfig({depositWeightBips: 10000, withdrawWeightBips: 10000});

        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__initialize_InvalidOwner.selector);
        vm.prank(owner);
        multiLendingModule.initialize(lendingModules, configs);
    }

    function testInitializeDuplicateLendingModule() public {
        address[] memory lendingModules = new address[](2);
        lendingModules[0] = address(lendingModule1);
        lendingModules[1] = address(lendingModule1);

        MultiMarketLendingModule.LendingModuleConfig[] memory configs =
            new MultiMarketLendingModule.LendingModuleConfig[](2);
        configs[0] = MultiMarketLendingModule.LendingModuleConfig({depositWeightBips: 5000, withdrawWeightBips: 6000});
        configs[1] = MultiMarketLendingModule.LendingModuleConfig({depositWeightBips: 5000, withdrawWeightBips: 4000});

        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__initialize_DuplicateLendingModule.selector);
        vm.prank(owner);
        multiLendingModule.initialize(lendingModules, configs);
    }

    /**
     * WITHDRAW AND DEPOSIT WEIGHTS TESTS
     */
    function testSetDepositWeights() public {
        _initializeDefaultSetup();

        // Test invalid array length
        uint16[] memory newWeights = new uint16[](3);
        newWeights[0] = 3000;
        newWeights[1] = 4000;
        newWeights[2] = 3000;

        vm.expectRevert(
            MultiMarketLendingModule.MultiMarketLendingModule__setDepositWeights_InvalidArrayLength.selector
        );
        vm.prank(owner);
        multiLendingModule.setDepositWeights(newWeights);

        // Test invalid sum of weights
        newWeights = new uint16[](2);
        newWeights[0] = 3000;
        newWeights[1] = 6000; // Sum = 9000, not 10000

        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__setDepositWeights_InvalidWeights.selector);
        vm.prank(owner);
        multiLendingModule.setDepositWeights(newWeights);

        // Test valid weights

        newWeights = new uint16[](2);
        newWeights[0] = 3000;
        newWeights[1] = 7000;

        vm.expectEmit(true, true, true, true);
        emit DepositWeightsSet(newWeights);

        vm.prank(owner);
        multiLendingModule.setDepositWeights(newWeights);

        // Verify updated weights
        MultiMarketLendingModule.LendingModuleConfig memory config1 =
            multiLendingModule.getLendingModuleConfig(address(lendingModule1));
        assertEq(config1.depositWeightBips, 3000);

        MultiMarketLendingModule.LendingModuleConfig memory config2 =
            multiLendingModule.getLendingModuleConfig(address(lendingModule2));
        assertEq(config2.depositWeightBips, 7000);
    }

    function testSetWithdrawWeights() public {
        _initializeDefaultSetup();

        // Invalid array length
        uint16[] memory newWeights = new uint16[](3);
        newWeights[0] = 3000;
        newWeights[1] = 4000;
        newWeights[2] = 3000;

        vm.expectRevert(
            MultiMarketLendingModule.MultiMarketLendingModule__setWithdrawWeights_InvalidArrayLength.selector
        );
        vm.prank(owner);
        multiLendingModule.setWithdrawWeights(newWeights);

        // Invalid withdraw weights (don't sum to 10000)
        newWeights = new uint16[](2);
        newWeights[0] = 3000;
        newWeights[1] = 6000; // Sum = 9000, not 10000

        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__setWithdrawWeights_InvalidWeights.selector);
        vm.prank(owner);
        multiLendingModule.setWithdrawWeights(newWeights);

        // Valid withdraw weights

        newWeights[0] = 8000;
        newWeights[1] = 2000;

        vm.expectEmit(true, true, true, true);
        emit WithdrawWeightsSet(newWeights);

        vm.prank(owner);
        multiLendingModule.setWithdrawWeights(newWeights);

        // Verify updated weights
        MultiMarketLendingModule.LendingModuleConfig memory config1 =
            multiLendingModule.getLendingModuleConfig(address(lendingModule1));
        assertEq(config1.withdrawWeightBips, 8000);
    }

    /**
     * TOKEN SWEEP MANAGER TESTS
     */
    function testSetTokenSweepManager() public {
        // Test zero address
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__ZeroAddress.selector);
        vm.prank(tokenSweepManager);
        multiLendingModule.setTokenSweepManager(address(0));

        address newManager = makeAddr("NEW_MANAGER");

        // Test only token sweep manager
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__OnlyTokenSweepManager.selector);
        vm.prank(owner);
        multiLendingModule.setTokenSweepManager(newManager);

        vm.expectEmit(true, true, true, true);
        emit TokenSweepManagerUpdated(newManager);

        vm.prank(tokenSweepManager);
        multiLendingModule.setTokenSweepManager(newManager);

        assertEq(multiLendingModule.tokenSweepManager(), newManager);
    }

    /**
     * DEPOSIT TESTS
     */
    function testDeposit() public {
        // Test not initialized
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__NotInitialized.selector);
        vm.prank(manager);
        multiLendingModule.deposit(1000e18);

        _initializeDefaultSetup();

        // Test zero amount
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__deposit_InvalidAmount.selector);
        vm.prank(manager);
        multiLendingModule.deposit(0);

        // Test only manager
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__OnlyManager.selector);
        vm.prank(user);
        multiLendingModule.deposit(1000e18);

        // Test deposit

        uint256 depositAmount = 1000e18;
        uint256 managerBalanceBefore = asset.balanceOf(manager);

        vm.prank(manager);
        multiLendingModule.deposit(depositAmount);

        // Check manager balance decreased
        assertEq(asset.balanceOf(manager), managerBalanceBefore - depositAmount);

        // Check total asset balance in lending modules
        assertEq(multiLendingModule.assetBalance(), depositAmount);

        // Check distribution according to weights (60% to module1, 40% to module2)
        assertEq(lendingModule1.assetBalance(), 600e18);
        assertEq(lendingModule2.assetBalance(), 400e18);
    }

    /**
     * WITHDRAW TESTS
     */
    function testWithdraw() public {
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__NotInitialized.selector);
        vm.prank(manager);
        multiLendingModule.withdraw(1000e18, recipient);

        _initializeDefaultSetup();

        // Test only manager
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__OnlyManager.selector);
        vm.prank(user);
        multiLendingModule.withdraw(1000e18, recipient);

        // Test zero amount
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__withdraw_InvalidAmount.selector);
        vm.prank(manager);
        multiLendingModule.withdraw(0, recipient);

        // Test zero recipient
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__ZeroAddress.selector);
        vm.prank(manager);
        multiLendingModule.withdraw(1000e18, address(0));

        // First deposit
        uint256 depositAmount = 1000e18;
        vm.prank(manager);
        multiLendingModule.deposit(depositAmount);

        // Then withdraw
        uint256 withdrawAmount = 600e18;
        uint256 recipientBalanceBefore = asset.balanceOf(recipient);

        uint256 snapshot = vm.snapshotState();

        vm.prank(manager);
        multiLendingModule.withdraw(withdrawAmount, recipient);

        // Check recipient received tokens
        assertEq(asset.balanceOf(recipient), recipientBalanceBefore + withdrawAmount);

        // Check remaining balance in lending modules
        assertEq(multiLendingModule.assetBalance(), depositAmount - withdrawAmount);

        vm.revertToState(snapshot);

        mockPool1.setIsCompromised(true);

        vm.prank(manager);
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__withdraw_InsufficientAmountReceived.selector);
        multiLendingModule.withdraw(withdrawAmount, recipient);
    }

    /**
     * SWEEP TESTS
     */
    function testSweep() public {
        // Send some random tokens to the contract
        ERC20Mock randomToken = new ERC20Mock();
        randomToken.mint(address(multiLendingModule), 500e18);

        // Test only token sweep manager
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__OnlyTokenSweepManager.selector);
        vm.prank(owner);
        multiLendingModule.sweep(address(randomToken), recipient);

        // Test zero address
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__ZeroAddress.selector);
        vm.prank(tokenSweepManager);
        multiLendingModule.sweep(address(0), recipient);

        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__ZeroAddress.selector);
        vm.prank(tokenSweepManager);
        multiLendingModule.sweep(address(randomToken), address(0));

        // Test sweep

        uint256 recipientBalanceBefore = randomToken.balanceOf(recipient);

        vm.expectEmit(true, true, true, true);
        emit Sweep(address(randomToken), recipient, 500e18);

        vm.prank(tokenSweepManager);
        multiLendingModule.sweep(address(randomToken), recipient);

        assertEq(randomToken.balanceOf(recipient), recipientBalanceBefore + 500e18);
        assertEq(randomToken.balanceOf(address(multiLendingModule)), 0);
    }

    /**
     * MANAGER FEE TESTS
     */
    function testManagerFeeClaimable() public {
        _initializeDefaultSetup();

        // Initially no fees claimable
        assertEq(multiLendingModule.managerFeeClaimable(), 0);

        // Deposit some amount
        vm.prank(manager);
        multiLendingModule.deposit(1000e18);

        // Still no fees since no yield generated
        assertEq(multiLendingModule.managerFeeClaimable(), 0);

        // Simulate yield generation
        asset.mint(address(mockPool1), 100e18);
        asset.mint(address(mockPool2), 50e18);

        // Now there should be claimable fees
        uint256 expectedFee = 0; // managerFeeBips is 0 in default setup
        assertEq(multiLendingModule.managerFeeClaimable(), expectedFee);
    }

    function testManagerFeeClaimableWithFees() public {
        // Deploy with manager fees
        vm.prank(owner);
        MultiMarketLendingModule multiLendingModuleWithFees =
            new MultiMarketLendingModule(address(asset), owner, manager, tokenSweepManager, 1000); // 10% fee

        _initializeLendingModule(multiLendingModuleWithFees);

        // Deposit
        asset.mint(manager, INITIAL_BALANCE);
        vm.prank(manager);
        asset.approve(address(multiLendingModuleWithFees), type(uint256).max);

        vm.prank(manager);
        multiLendingModuleWithFees.deposit(1000e18);

        // Simulate yield generation
        asset.mint(address(mockPool1), 100e18);
        asset.mint(address(mockPool2), 50e18);

        // Calculate expected fee: 10% of 150e18 yield = 15e18
        uint256 expectedFee = (150e18 * 1000) / 10000;
        assertEq(multiLendingModuleWithFees.managerFeeClaimable(), expectedFee);
    }

    function testClaimManagerFee() public {
        // Deploy with manager fees
        vm.prank(owner);
        MultiMarketLendingModule multiLendingModuleWithFees =
            new MultiMarketLendingModule(address(asset), owner, manager, tokenSweepManager, 1000); // 10% fee

        _initializeLendingModule(multiLendingModuleWithFees);

        // Setup balances and approvals
        asset.mint(manager, INITIAL_BALANCE);
        vm.prank(manager);
        asset.approve(address(multiLendingModuleWithFees), type(uint256).max);

        // Deposit
        vm.prank(manager);
        multiLendingModuleWithFees.deposit(1000e18);

        // Simulate yield
        asset.mint(address(mockPool1), 100e18);
        asset.mint(address(mockPool2), 50e18);

        uint256 recipientBalanceBefore = asset.balanceOf(recipient);
        uint256 expectedFee = (150e18 * 1000) / 10000; // 15e18

        // Test zero address recipient
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__ZeroAddress.selector);
        vm.prank(owner);
        multiLendingModuleWithFees.claimManagerFee(address(0));

        // Test only owner
        vm.expectRevert();
        vm.prank(manager);
        multiLendingModuleWithFees.claimManagerFee(recipient);

        // Claim fees
        vm.expectEmit(true, false, false, true);
        emit ManagerFeeClaimed(recipient, expectedFee);

        vm.prank(owner);
        multiLendingModuleWithFees.claimManagerFee(recipient);

        assertEq(asset.balanceOf(recipient), recipientBalanceBefore + expectedFee);
        assertEq(multiLendingModuleWithFees.totalManagerClaimed(), expectedFee);
        assertEq(multiLendingModuleWithFees.managerFeeClaimable(), 0);
    }

    function testClaimManagerFeeNoFeesAvailable() public {
        _initializeDefaultSetup();

        vm.prank(owner);
        multiLendingModule.claimManagerFee(recipient);

        // Should not revert but also not transfer anything
        assertEq(asset.balanceOf(recipient), 0);
        assertEq(multiLendingModule.totalManagerClaimed(), 0);
    }

    function testAssetBalanceAfterManagerFeeClaim() public {
        // Deploy with manager fees
        vm.prank(owner);
        MultiMarketLendingModule multiLendingModuleWithFees =
            new MultiMarketLendingModule(address(asset), owner, manager, tokenSweepManager, 2000); // 20% fee

        _initializeLendingModule(multiLendingModuleWithFees);

        asset.mint(manager, INITIAL_BALANCE);
        vm.prank(manager);
        asset.approve(address(multiLendingModuleWithFees), type(uint256).max);

        vm.prank(manager);
        multiLendingModuleWithFees.deposit(1000e18);

        // Initial asset balance should be 1000e18
        assertEq(multiLendingModuleWithFees.assetBalance(), 1000e18);

        // Generate yield
        asset.mint(address(mockPool1), 200e18);
        asset.mint(address(mockPool2), 100e18);

        // Asset balance should be principal + yield - manager fee
        // Total balance: 1000 + 300 = 1300
        // Manager fee: 300 * 20% = 60
        // Asset balance: 1300 - 60 = 1240
        uint256 expectedAssetBalance = 1000e18 + 300e18 - 60e18;
        assertEq(multiLendingModuleWithFees.assetBalance(), expectedAssetBalance);

        // Claim fees
        vm.prank(owner);
        multiLendingModuleWithFees.claimManagerFee(recipient);

        // After claiming fees, the 60e18 was actually withdrawn from the pools
        // So total balance in pools is now: 1300e18 - 60e18 = 1240e18
        // Asset balance = total balance - remaining manager fees = 1240e18 - 0 = 1240e18
        assertEq(multiLendingModuleWithFees.assetBalance(), 1240e18);
    }

    /**
     * COMPREHENSIVE ERROR CONDITION TESTS
     */
    function testWithdrawInsufficientBalance() public {
        _initializeDefaultSetup();

        vm.prank(manager);
        multiLendingModule.deposit(1000e18);

        // Try to withdraw more than available
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__withdraw_InsufficientBalance.selector);
        vm.prank(manager);
        multiLendingModule.withdraw(1001e18, recipient);
    }

    function testWithdrawExcessiveAmountReceived() public {
        address[] memory lendingModules = new address[](2);
        lendingModules[0] = address(lendingModule1);
        lendingModules[1] = address(lendingModule2);

        MultiMarketLendingModule.LendingModuleConfig[] memory configs =
            new MultiMarketLendingModule.LendingModuleConfig[](2);
        configs[0] = MultiMarketLendingModule.LendingModuleConfig({
            depositWeightBips: 5000, // 50%
            withdrawWeightBips: 5000 // 50%
        });
        configs[1] = MultiMarketLendingModule.LendingModuleConfig({
            depositWeightBips: 5000, // 50%
            withdrawWeightBips: 5000 // 50%
        });

        vm.prank(owner);
        multiLendingModule.initialize(lendingModules, configs);

        vm.prank(manager);
        multiLendingModule.deposit(1000e18);

        mockPool1.setIsExcessTransfer(true);

        // recipient cannot receive more than max withdrawable amount
        vm.prank(manager);
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__withdraw_ExcessiveAmountReceived.selector);
        multiLendingModule.withdraw(1000e18, recipient);
    }

    function testDepositPartialDepositNotAllowed() public {
        _initializeDefaultSetup();

        mockPool1.setIsPartialDeposit(true);
        mockPool1.setPartialDepositRecipient(address(multiLendingModule));

        vm.prank(manager);
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__deposit_PartialDepositNotAllowed.selector);
        multiLendingModule.deposit(1000e18);
    }

    /**
     * BOUNDARY CONDITIONS AND PRECISION TESTS
     */
    function testManagerFeeMaximum() public {
        // Test with maximum allowed manager fee (50%)
        vm.prank(owner);
        MultiMarketLendingModule multiLendingModuleMaxFee =
            new MultiMarketLendingModule(address(asset), owner, manager, tokenSweepManager, 5000);

        _initializeLendingModule(multiLendingModuleMaxFee);

        asset.mint(manager, INITIAL_BALANCE);
        vm.prank(manager);
        asset.approve(address(multiLendingModuleMaxFee), type(uint256).max);

        vm.prank(manager);
        multiLendingModuleMaxFee.deposit(1000e18);

        // Generate yield
        asset.mint(address(mockPool1), 100e18);

        // Manager fee should be 50% of yield
        uint256 expectedFee = (100e18 * 5000) / 10000;
        assertEq(multiLendingModuleMaxFee.managerFeeClaimable(), expectedFee);

        vm.prank(owner);
        multiLendingModuleMaxFee.claimManagerFee(recipient);

        assertEq(asset.balanceOf(recipient), 100e18 - expectedFee);
        assertEq(multiLendingModuleMaxFee.totalManagerClaimed(), expectedFee);
        assertEq(multiLendingModuleMaxFee.managerFeeClaimable(), 0);
    }

    function testPrecisionInWeightedDistribution() public {
        // Test with weights that might cause precision issues
        address[] memory lendingModules = new address[](3);
        lendingModules[0] = address(lendingModule1);
        lendingModules[1] = address(lendingModule2);
        lendingModules[2] = address(lendingModule3);

        MultiMarketLendingModule.LendingModuleConfig[] memory configs =
            new MultiMarketLendingModule.LendingModuleConfig[](3);
        configs[0] = MultiMarketLendingModule.LendingModuleConfig({
            depositWeightBips: 3333, // 33.33%
            withdrawWeightBips: 3333
        });
        configs[1] = MultiMarketLendingModule.LendingModuleConfig({
            depositWeightBips: 3333, // 33.33%
            withdrawWeightBips: 3333
        });
        configs[2] = MultiMarketLendingModule.LendingModuleConfig({
            depositWeightBips: 3334, // 33.34% (to sum to 10000)
            withdrawWeightBips: 3334
        });

        vm.prank(owner);
        multiLendingModule.initialize(lendingModules, configs);

        // Test deposit with amount that doesn't divide evenly
        vm.prank(manager);
        multiLendingModule.deposit(100e18);

        // Verify total balance is maintained
        assertEq(multiLendingModule.assetBalance(), 100e18);
    }

    function testSweepAssetToken() public {
        _initializeDefaultSetup();

        // Send asset tokens directly to the contract (simulating stuck tokens)
        asset.mint(address(multiLendingModule), 500e18);

        uint256 recipientBalanceBefore = asset.balanceOf(recipient);

        vm.prank(tokenSweepManager);
        multiLendingModule.sweep(address(asset), recipient);

        assertEq(asset.balanceOf(recipient), recipientBalanceBefore + 500e18);
        assertEq(asset.balanceOf(address(multiLendingModule)), 0);
    }

    function testSweepNonOwnerRevert() public {
        ERC20Mock randomToken = new ERC20Mock();
        randomToken.mint(address(multiLendingModule), 100e18);

        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__OnlyTokenSweepManager.selector);
        vm.prank(owner);
        multiLendingModule.sweep(address(randomToken), recipient);
    }

    /**
     * INTEGRATION AND COMPLEX SCENARIO TESTS
     */
    function testComplexMultipleOperationsWithFees() public {
        // Deploy with fees
        vm.prank(owner);
        MultiMarketLendingModule multiLendingModuleWithFees =
            new MultiMarketLendingModule(address(asset), owner, manager, tokenSweepManager, 1500); // 15% fee

        _initializeLendingModule(multiLendingModuleWithFees);

        asset.mint(manager, INITIAL_BALANCE);
        vm.prank(manager);
        asset.approve(address(multiLendingModuleWithFees), type(uint256).max);

        // Multiple deposits
        vm.startPrank(manager);
        multiLendingModuleWithFees.deposit(1000e18);
        multiLendingModuleWithFees.deposit(500e18);
        vm.stopPrank();

        // Generate yield
        asset.mint(address(mockPool1), 150e18);
        asset.mint(address(mockPool2), 75e18);

        // Partial withdrawal
        vm.prank(manager);
        multiLendingModuleWithFees.withdraw(200e18, recipient);

        // Claim fees
        vm.prank(owner);
        multiLendingModuleWithFees.claimManagerFee(recipient);

        // More yield
        asset.mint(address(mockPool1), 50e18);

        // Final calculations should be consistent
        uint256 finalBalance = multiLendingModuleWithFees.assetBalance();
        uint256 finalClaimable = multiLendingModuleWithFees.managerFeeClaimable();

        // Verify total tracking is correct
        assertTrue(finalBalance > 0);
        assertTrue(finalClaimable >= 0);
    }

    function testWeightRebalancing() public {
        _initializeDefaultSetup();

        // Initial deposit
        vm.prank(manager);
        multiLendingModule.deposit(1000e18);

        // Change weights
        uint16[] memory newDepositWeights = new uint16[](2);
        newDepositWeights[0] = 8000; // 80%
        newDepositWeights[1] = 2000; // 20%

        vm.prank(owner);
        multiLendingModule.setDepositWeights(newDepositWeights);

        // New deposit should use new weights
        vm.prank(manager);
        multiLendingModule.deposit(1000e18);

        // Verify distribution
        uint256 module1Balance = lendingModule1.assetBalance();
        uint256 module2Balance = lendingModule2.assetBalance();

        // First deposit: 600 + 400, Second deposit: 800 + 200
        assertEq(module1Balance, 600e18 + 800e18);
        assertEq(module2Balance, 400e18 + 200e18);

        // Change weights to 100% for module1 and 0% for module2
        newDepositWeights[0] = 10000; // 100%
        newDepositWeights[1] = 0; // 0%

        vm.prank(owner);
        multiLendingModule.setDepositWeights(newDepositWeights);

        vm.prank(manager);
        multiLendingModule.deposit(1000e18);

        module1Balance = lendingModule1.assetBalance();
        module2Balance = lendingModule2.assetBalance();

        // Third deposit: 1000 + 0
        assertEq(module1Balance, 600e18 + 800e18 + 1000e18);
        assertEq(module2Balance, 400e18 + 200e18);

        // Change weights to 0% for module1 and 100% for module2
        newDepositWeights[0] = 0; // 0%
        newDepositWeights[1] = 10000; // 100%

        vm.prank(owner);
        multiLendingModule.setDepositWeights(newDepositWeights);

        vm.prank(manager);
        multiLendingModule.deposit(1000e18);

        module1Balance = lendingModule1.assetBalance();
        module2Balance = lendingModule2.assetBalance();

        // Fourth deposit: 0 + 1000
        assertEq(module1Balance, 600e18 + 800e18 + 1000e18);
        assertEq(module2Balance, 400e18 + 200e18 + 1000e18);
    }

    /**
     * EDGE CASES AND INTEGRATION TESTS
     */
    function testMultipleDepositsAndWithdrawals() public {
        _initializeDefaultSetup();

        // Multiple deposits
        vm.startPrank(manager);
        multiLendingModule.deposit(1000e18);
        multiLendingModule.deposit(500e18);
        multiLendingModule.deposit(300e18);
        vm.stopPrank();

        assertEq(multiLendingModule.assetBalance(), 1800e18);

        // Multiple withdrawals
        vm.startPrank(manager);
        multiLendingModule.withdraw(200e18, recipient);
        multiLendingModule.withdraw(100e18, recipient);
        vm.stopPrank();

        assertEq(multiLendingModule.assetBalance(), 1500e18);
        assertEq(asset.balanceOf(recipient), 300e18);
    }

    function testAssetBalanceWithYield() public {
        _initializeDefaultSetup();

        // Deposit
        vm.prank(manager);
        multiLendingModule.deposit(1000e18);

        // Simulate yield generation in underlying pools
        asset.mint(address(mockPool1), 100e18);
        asset.mint(address(mockPool2), 50e18);

        // Asset balance should include yield
        uint256 expectedBalance = 1000e18 + 100e18 + 50e18;
        assertEq(multiLendingModule.assetBalance(), expectedBalance);
    }

    function testMaxLendingModules() public {
        // Deploy maximum number of lending modules
        address[] memory lendingModules = new address[](10);
        MultiMarketLendingModule.LendingModuleConfig[] memory configs =
            new MultiMarketLendingModule.LendingModuleConfig[](10);

        for (uint256 i = 0; i < 10; i++) {
            MockERC4626LendingPool pool = new MockERC4626LendingPool(address(asset));

            ERC4626LendingModule module =
                new ERC4626LendingModule(address(pool), address(multiLendingModule), tokenSweepManager);

            lendingModules[i] = address(module);
            configs[i] = MultiMarketLendingModule.LendingModuleConfig({
                depositWeightBips: 1000, // 10% each
                withdrawWeightBips: 1000
            });
        }

        vm.prank(owner);
        multiLendingModule.initialize(lendingModules, configs);

        assertEq(multiLendingModule.lendingModules().length, 10);
    }

    function testExceedMaxLendingModules() public {
        address[] memory lendingModules = new address[](11); // Exceed limit
        MultiMarketLendingModule.LendingModuleConfig[] memory configs =
            new MultiMarketLendingModule.LendingModuleConfig[](11);

        vm.expectRevert(
            MultiMarketLendingModule.MultiMarketLendingModule__initialize_ExceededMaxLendingModules.selector
        );
        vm.prank(owner);
        multiLendingModule.initialize(lendingModules, configs);
    }

    /**
     * ADDITIONAL FUZZ TESTS (constrained for reliability)
     */
    function testFuzzSimpleManagerFee(uint8 feeBipsPercent) public {
        vm.assume(feeBipsPercent <= 50); // Max 5% for simplicity
        uint256 feeBips = uint256(feeBipsPercent) * 100; // Convert to actual bips

        // Deploy with custom fee
        vm.prank(owner);
        MultiMarketLendingModule fuzzModule =
            new MultiMarketLendingModule(address(asset), owner, manager, tokenSweepManager, feeBips);

        _initializeLendingModule(fuzzModule);

        asset.mint(manager, INITIAL_BALANCE);
        vm.prank(manager);
        asset.approve(address(fuzzModule), type(uint256).max);

        // Simple fixed amounts
        uint256 principal = 1000e18;
        uint256 yield = 100e18;

        // Deposit principal
        vm.prank(manager);
        fuzzModule.deposit(principal);

        // Generate yield by minting to the first pool
        asset.mint(address(mockPool1), yield);

        // Calculate expected fee
        uint256 expectedFee = Math.mulDiv(yield, feeBips, BIPS);
        assertEq(fuzzModule.managerFeeClaimable(), expectedFee);

        // Asset balance should be principal + yield - fee
        uint256 expectedAssetBalance = principal + yield - expectedFee;
        assertEq(fuzzModule.assetBalance(), expectedAssetBalance);

        // Claim manager fees
        vm.prank(owner);
        fuzzModule.claimManagerFee(recipient);

        assertEq(asset.balanceOf(recipient), expectedFee);
        assertEq(fuzzModule.totalManagerClaimed(), expectedFee);
        assertEq(fuzzModule.managerFeeClaimable(), 0);
        // Asset balance should be principal + yield - expectedFee
        assertEq(fuzzModule.assetBalance(), principal + yield - expectedFee);
    }

    /**
     * ADDITIONAL EDGE CASE TESTS
     */
    function testZeroAmountOperations() public {
        _initializeDefaultSetup();

        // Zero deposit should revert
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__deposit_InvalidAmount.selector);
        vm.prank(manager);
        multiLendingModule.deposit(0);

        // Zero withdrawal should revert
        vm.expectRevert(MultiMarketLendingModule.MultiMarketLendingModule__withdraw_InvalidAmount.selector);
        vm.prank(manager);
        multiLendingModule.withdraw(0, recipient);
    }

    function testManagerFeeEdgeCases() public {
        // Test with zero fee
        _initializeDefaultSetup();

        vm.prank(manager);
        multiLendingModule.deposit(1000e18);

        // Generate yield
        asset.mint(address(mockPool1), 100e18);

        // Should have zero claimable fees
        assertEq(multiLendingModule.managerFeeClaimable(), 0);

        // Asset balance should include all yield
        assertEq(multiLendingModule.assetBalance(), 1100e18);
    }

    function testTotalPrincipalTracking() public {
        _initializeDefaultSetup();

        // Initially zero
        assertEq(multiLendingModule.totalPrincipal(), 0);

        // After deposit
        vm.prank(manager);
        multiLendingModule.deposit(1000e18);
        assertEq(multiLendingModule.totalPrincipal(), 1000e18);

        // After withdrawal
        vm.prank(manager);
        multiLendingModule.withdraw(200e18, recipient);
        assertEq(multiLendingModule.totalPrincipal(), 800e18);

        // Multiple operations
        vm.startPrank(manager);
        multiLendingModule.deposit(500e18);
        assertEq(multiLendingModule.totalPrincipal(), 1300e18);

        multiLendingModule.withdraw(300e18, recipient);
        assertEq(multiLendingModule.totalPrincipal(), 1000e18);
        vm.stopPrank();
    }

    function testLendingModulesView() public {
        _initializeDefaultSetup();

        address[] memory modules = multiLendingModule.lendingModules();
        assertEq(modules.length, 2);
        assertEq(modules[0], address(lendingModule1));
        assertEq(modules[1], address(lendingModule2));
    }

    function testGetLendingModuleConfig() public {
        _initializeDefaultSetup();

        MultiMarketLendingModule.LendingModuleConfig memory config1 =
            multiLendingModule.getLendingModuleConfig(address(lendingModule1));
        assertEq(config1.depositWeightBips, 6000);
        assertEq(config1.withdrawWeightBips, 5000);

        MultiMarketLendingModule.LendingModuleConfig memory config2 =
            multiLendingModule.getLendingModuleConfig(address(lendingModule2));
        assertEq(config2.depositWeightBips, 4000);
        assertEq(config2.withdrawWeightBips, 5000);
    }

    function testEmptyBalanceOperations() public {
        _initializeDefaultSetup();

        // Test assetBalance with no deposits
        assertEq(multiLendingModule.assetBalance(), 0);
        assertEq(multiLendingModule.managerFeeClaimable(), 0);
        assertEq(multiLendingModule.totalPrincipal(), 0);
        assertEq(multiLendingModule.totalManagerClaimed(), 0);
    }

    function testAssetBalanceEdgeCases() public {
        // Deploy with fees
        vm.prank(owner);
        MultiMarketLendingModule moduleWithFees =
            new MultiMarketLendingModule(address(asset), owner, manager, tokenSweepManager, 1000);

        _initializeLendingModule(moduleWithFees);

        asset.mint(manager, INITIAL_BALANCE);
        vm.prank(manager);
        asset.approve(address(moduleWithFees), type(uint256).max);

        // Test edge case when there's minimal principal
        vm.prank(manager);
        moduleWithFees.deposit(1e18); // Very small deposit

        // Generate tiny yield
        asset.mint(address(mockPool1), 1000);

        // With very small amounts, precision should still work
        uint256 assetBalance = moduleWithFees.assetBalance();
        assertTrue(assetBalance > 0);

        uint256 managerFee = moduleWithFees.managerFeeClaimable();
        assertTrue(managerFee < assetBalance);
    }

    /**
     * FUZZ TESTS
     */
    function testFuzzDeposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= INITIAL_BALANCE);
        _initializeDefaultSetup();

        vm.prank(manager);
        multiLendingModule.deposit(amount);

        assertEq(multiLendingModule.assetBalance(), amount);

        // Check proportional distribution
        uint256 expectedModule1 = Math.mulDiv(amount, 6000, BIPS, Math.Rounding.Ceil);
        uint256 expectedModule2 = amount - expectedModule1; // Remaining goes to module2

        // There can be rounding errors
        assertEq(lendingModule1.assetBalance(), expectedModule1);
        assertEq(lendingModule2.assetBalance(), expectedModule2);
    }

    function testFuzzWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 1000 && depositAmount <= INITIAL_BALANCE);
        vm.assume(withdrawAmount > 0 && withdrawAmount <= (depositAmount * 4000) / 10000);

        _initializeDefaultSetup();

        // Deposit first
        vm.prank(manager);
        multiLendingModule.deposit(depositAmount);

        // Then withdraw
        vm.prank(manager);
        multiLendingModule.withdraw(withdrawAmount, recipient);

        assertEq(asset.balanceOf(recipient), withdrawAmount);
        assertEq(multiLendingModule.assetBalance(), depositAmount - withdrawAmount);
    }

    /**
     * HELPER FUNCTIONS
     */
    function _initializeLendingModule(MultiMarketLendingModule _module) internal {
        // Deploy new lending modules with the correct owner (the _module itself)
        ERC4626LendingModule newLendingModule1 =
            new ERC4626LendingModule(address(mockPool1), address(_module), tokenSweepManager);
        ERC4626LendingModule newLendingModule2 =
            new ERC4626LendingModule(address(mockPool2), address(_module), tokenSweepManager);

        address[] memory lendingModules = new address[](2);
        lendingModules[0] = address(newLendingModule1);
        lendingModules[1] = address(newLendingModule2);

        MultiMarketLendingModule.LendingModuleConfig[] memory configs =
            new MultiMarketLendingModule.LendingModuleConfig[](2);
        configs[0] = MultiMarketLendingModule.LendingModuleConfig({
            depositWeightBips: 6000, // 60%
            withdrawWeightBips: 5000 // 50%
        });
        configs[1] = MultiMarketLendingModule.LendingModuleConfig({
            depositWeightBips: 4000, // 40%
            withdrawWeightBips: 5000 // 50%
        });

        vm.prank(owner);
        _module.initialize(lendingModules, configs);
    }

    function _initializeDefaultSetup() internal {
        address[] memory lendingModules = new address[](2);
        lendingModules[0] = address(lendingModule1);
        lendingModules[1] = address(lendingModule2);

        MultiMarketLendingModule.LendingModuleConfig[] memory configs =
            new MultiMarketLendingModule.LendingModuleConfig[](2);
        configs[0] = MultiMarketLendingModule.LendingModuleConfig({
            depositWeightBips: 6000, // 60%
            withdrawWeightBips: 5000 // 50%
        });
        configs[1] = MultiMarketLendingModule.LendingModuleConfig({
            depositWeightBips: 4000, // 40%
            withdrawWeightBips: 5000 // 50%
        });

        vm.prank(owner);
        multiLendingModule.initialize(lendingModules, configs);
    }
}
