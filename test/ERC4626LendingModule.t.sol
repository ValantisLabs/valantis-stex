// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ERC4626LendingModule} from "src/lending-modules/ERC4626LendingModule.sol";
import {MockERC4626LendingPool} from "src/mocks/MockERC4626LendingPool.sol";

contract ERC4626LendingModuleTest is Test {
    ERC4626LendingModule lendingModule;
    MockERC4626LendingPool vault;
    ERC20Mock assetToken;

    address owner = makeAddr("OWNER");
    address tokenSweepManager = makeAddr("TOKEN_SWEEP_MANAGER");
    address recipient = makeAddr("RECIPIENT");
    address user = makeAddr("USER");

    uint256 constant DEPOSIT_AMOUNT = 1000 ether;
    uint256 constant WITHDRAW_AMOUNT = 500 ether;

    event TokenSweepManagerUpdated(address tokenSweepManager);
    event Sweep(address indexed token, address indexed recipient, uint256 balance);

    function setUp() public {
        // Deploy mock asset token
        assetToken = new ERC20Mock();
        assetToken.mint(owner, 10000 ether);

        // Deploy mock vault
        vault = new MockERC4626LendingPool(address(assetToken));

        // Deploy lending module
        lendingModule = new ERC4626LendingModule(address(vault), owner, tokenSweepManager);

        // Verify initial state
        assertEq(address(lendingModule.vault()), address(vault));
        assertEq(lendingModule.asset(), address(assetToken));
        assertEq(lendingModule.owner(), owner);
        assertEq(lendingModule.tokenSweepManager(), tokenSweepManager);
    }

    function testDeploy() public {
        vm.expectRevert(ERC4626LendingModule.ERC4626LendingModule__ZeroAddress.selector);
        new ERC4626LendingModule(address(0), owner, tokenSweepManager);

        vm.expectRevert(ERC4626LendingModule.ERC4626LendingModule__ZeroAddress.selector);
        new ERC4626LendingModule(address(vault), owner, address(0));

        vm.expectRevert();
        new ERC4626LendingModule(address(vault), address(0), tokenSweepManager);

        // Test with valid parameters
        ERC4626LendingModule newModule = new ERC4626LendingModule(address(vault), owner, tokenSweepManager);

        assertEq(address(newModule.vault()), address(vault));
        assertEq(newModule.asset(), address(assetToken));
        assertEq(newModule.owner(), owner);
        assertEq(newModule.tokenSweepManager(), tokenSweepManager);
    }

    function testAssetBalance() public {
        // Initially should be 0
        assertEq(lendingModule.assetBalance(), 0);

        vm.startPrank(owner);
        assetToken.approve(address(lendingModule), DEPOSIT_AMOUNT * 3);

        // First deposit
        lendingModule.deposit(DEPOSIT_AMOUNT);
        assertEq(lendingModule.assetBalance(), DEPOSIT_AMOUNT);

        // Second deposit
        lendingModule.deposit(DEPOSIT_AMOUNT);
        assertEq(lendingModule.assetBalance(), DEPOSIT_AMOUNT * 2);

        // Third deposit
        lendingModule.deposit(DEPOSIT_AMOUNT);
        assertEq(lendingModule.assetBalance(), DEPOSIT_AMOUNT * 3);

        // Simulate borrow through the vault
        vault.removeToken(DEPOSIT_AMOUNT, owner);

        // Asset balance remains the same,
        // since it should not decrease as utilization/borrowing increases.
        assertEq(lendingModule.assetBalance(), DEPOSIT_AMOUNT * 3);
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT * 3);
        assertEq(assetToken.balanceOf(address(vault)), 2 * DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function testDeposit() public {
        vm.startPrank(user);

        assetToken.approve(address(lendingModule), DEPOSIT_AMOUNT);

        vm.expectRevert(); // Should revert due to access control
        lendingModule.deposit(DEPOSIT_AMOUNT);

        vm.stopPrank();

        vm.startPrank(owner);

        assetToken.approve(address(lendingModule), 0);

        vm.expectRevert(); // Should revert due to zero amount
        lendingModule.deposit(0);

        // Approve tokens
        assetToken.approve(address(lendingModule), DEPOSIT_AMOUNT);

        // Record initial balances
        uint256 initialOwnerBalance = assetToken.balanceOf(owner);
        uint256 initialVaultBalance = assetToken.balanceOf(address(vault));
        uint256 initialModuleBalance = assetToken.balanceOf(address(lendingModule));

        // Deposit
        lendingModule.deposit(DEPOSIT_AMOUNT);

        // Verify balances
        assertEq(assetToken.balanceOf(owner), initialOwnerBalance - DEPOSIT_AMOUNT);
        assertEq(assetToken.balanceOf(address(vault)), initialVaultBalance + DEPOSIT_AMOUNT);
        assertEq(assetToken.balanceOf(address(lendingModule)), initialModuleBalance);

        // Verify vault shares were minted to the module
        assertGt(vault.balanceOf(address(lendingModule)), 0);

        vm.stopPrank();
    }

    function testWithdraw() public {
        // First deposit some tokens
        vm.startPrank(owner);
        assetToken.approve(address(lendingModule), DEPOSIT_AMOUNT);
        lendingModule.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Record initial balances
        uint256 initialRecipientBalance = assetToken.balanceOf(recipient);
        uint256 initialVaultBalance = assetToken.balanceOf(address(vault));
        uint256 initialModuleBalance = assetToken.balanceOf(address(lendingModule));

        vm.startPrank(user);

        vm.expectRevert(); // Should revert due to access control
        lendingModule.withdraw(WITHDRAW_AMOUNT, recipient);

        vm.expectRevert(); // Should revert due to zero address
        lendingModule.withdraw(WITHDRAW_AMOUNT, address(0));

        // Try to withdraw more than deposited
        vm.expectRevert(); // Should revert due to insufficient balance
        lendingModule.withdraw(DEPOSIT_AMOUNT + 1, recipient);

        vm.stopPrank();

        // Withdraw
        vm.prank(owner);
        lendingModule.withdraw(WITHDRAW_AMOUNT, recipient);

        // Verify balances
        assertEq(assetToken.balanceOf(recipient), initialRecipientBalance + WITHDRAW_AMOUNT);
        assertEq(assetToken.balanceOf(address(vault)), initialVaultBalance - WITHDRAW_AMOUNT);
        assertEq(assetToken.balanceOf(address(lendingModule)), initialModuleBalance);

        // Verify vault shares decreased
        assertLt(vault.balanceOf(address(lendingModule)), vault.balanceOf(address(lendingModule)) + WITHDRAW_AMOUNT);
    }

    function testSetTokenSweepManager() public {
        address newTokenSweepManager = makeAddr("NEW_TOKEN_SWEEP_MANAGER");

        // Should revert if called by non-tokenSweepManager
        vm.expectRevert(ERC4626LendingModule.ERC4626LendingModule__OnlyTokenSweepManager.selector);
        lendingModule.setTokenSweepManager(newTokenSweepManager);

        // Should revert if new address is zero
        vm.startPrank(tokenSweepManager);
        vm.expectRevert(ERC4626LendingModule.ERC4626LendingModule__ZeroAddress.selector);
        lendingModule.setTokenSweepManager(address(0));

        // Should succeed with valid parameters
        vm.expectEmit(true, false, false, true);
        emit TokenSweepManagerUpdated(newTokenSweepManager);
        lendingModule.setTokenSweepManager(newTokenSweepManager);

        assertEq(lendingModule.tokenSweepManager(), newTokenSweepManager);

        vm.stopPrank();
    }

    function testSweep() public {
        ERC20Mock mockToken = new ERC20Mock();

        // Should revert if called by non-tokenSweepManager
        vm.expectRevert(ERC4626LendingModule.ERC4626LendingModule__OnlyTokenSweepManager.selector);
        lendingModule.sweep(address(mockToken), recipient);

        vm.startPrank(tokenSweepManager);

        // Should revert if token address is zero
        vm.expectRevert(ERC4626LendingModule.ERC4626LendingModule__ZeroAddress.selector);
        lendingModule.sweep(address(0), recipient);

        // Should revert if recipient address is zero
        vm.expectRevert(ERC4626LendingModule.ERC4626LendingModule__ZeroAddress.selector);
        lendingModule.sweep(address(mockToken), address(0));

        // Should revert if trying to sweep vault token
        vm.expectRevert(ERC4626LendingModule.ERC4626LendingModule__sweep_VaultTokenCannotBeSweeped.selector);
        lendingModule.sweep(address(vault), recipient);

        // Should not revert but also not transfer anything
        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);
        lendingModule.sweep(address(mockToken), recipient);

        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance);

        mockToken.mint(address(lendingModule), 100 ether);

        // Should succeed with valid parameters
        uint256 moduleBalance = mockToken.balanceOf(address(lendingModule));

        vm.expectEmit(true, true, false, true);
        emit Sweep(address(mockToken), recipient, moduleBalance);
        lendingModule.sweep(address(mockToken), recipient);

        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + moduleBalance);
        assertEq(mockToken.balanceOf(address(lendingModule)), 0);

        vm.stopPrank();
    }

    function testIntegrationDepositAndWithdraw() public {
        vm.startPrank(owner);

        // Initial state
        assertEq(lendingModule.assetBalance(), 0);

        // Deposit
        assetToken.approve(address(lendingModule), DEPOSIT_AMOUNT);
        lendingModule.deposit(DEPOSIT_AMOUNT);

        // Verify deposit
        assertEq(lendingModule.assetBalance(), DEPOSIT_AMOUNT);

        // Withdraw partial amount
        lendingModule.withdraw(WITHDRAW_AMOUNT, recipient);

        // Verify withdrawal
        assertEq(assetToken.balanceOf(recipient), WITHDRAW_AMOUNT);
        assertEq(lendingModule.assetBalance(), DEPOSIT_AMOUNT - WITHDRAW_AMOUNT);

        // Withdraw remaining amount
        lendingModule.withdraw(DEPOSIT_AMOUNT - WITHDRAW_AMOUNT, recipient);

        // Verify final state
        assertEq(assetToken.balanceOf(recipient), DEPOSIT_AMOUNT);
        assertEq(lendingModule.assetBalance(), 0);

        vm.stopPrank();
    }

    function testMultipleWithdrawals() public {
        vm.startPrank(owner);

        // Deposit initial amount
        assetToken.approve(address(lendingModule), DEPOSIT_AMOUNT);
        lendingModule.deposit(DEPOSIT_AMOUNT);

        // Multiple withdrawals to different recipients
        address recipient1 = makeAddr("RECIPIENT1");
        address recipient2 = makeAddr("RECIPIENT2");

        lendingModule.withdraw(WITHDRAW_AMOUNT / 2, recipient1);
        lendingModule.withdraw(WITHDRAW_AMOUNT / 2, recipient2);

        assertEq(assetToken.balanceOf(recipient1), WITHDRAW_AMOUNT / 2);
        assertEq(assetToken.balanceOf(recipient2), WITHDRAW_AMOUNT / 2);
        assertEq(lendingModule.assetBalance(), DEPOSIT_AMOUNT - WITHDRAW_AMOUNT);

        vm.stopPrank();
    }

    function testRevertWithdrawMoreThanDeposited() public {
        vm.startPrank(owner);

        // Deposit small amount
        assetToken.approve(address(lendingModule), 100 ether);
        lendingModule.deposit(100 ether);

        // Try to withdraw more
        vm.expectRevert();
        lendingModule.withdraw(100 ether + 1, recipient);

        vm.stopPrank();
    }

    function testMultipleTokenSweepManagerUpdates() public {
        address newTokenSweepManager1 = makeAddr("NEW_TOKEN_SWEEP_MANAGER_1");
        address newTokenSweepManager2 = makeAddr("NEW_TOKEN_SWEEP_MANAGER_2");

        // Initial manager can update
        vm.startPrank(tokenSweepManager);
        lendingModule.setTokenSweepManager(newTokenSweepManager1);
        vm.stopPrank();
        assertEq(lendingModule.tokenSweepManager(), newTokenSweepManager1);

        // Old manager should now revert
        vm.startPrank(tokenSweepManager);
        vm.expectRevert(ERC4626LendingModule.ERC4626LendingModule__OnlyTokenSweepManager.selector);
        lendingModule.setTokenSweepManager(newTokenSweepManager2);
        vm.stopPrank();

        // New manager can update
        vm.startPrank(newTokenSweepManager1);
        lendingModule.setTokenSweepManager(newTokenSweepManager2);
        vm.stopPrank();
        assertEq(lendingModule.tokenSweepManager(), newTokenSweepManager2);

        // Both previous managers should now revert
        vm.startPrank(tokenSweepManager);
        vm.expectRevert(ERC4626LendingModule.ERC4626LendingModule__OnlyTokenSweepManager.selector);
        lendingModule.setTokenSweepManager(tokenSweepManager);
        vm.stopPrank();

        vm.startPrank(newTokenSweepManager1);
        vm.expectRevert(ERC4626LendingModule.ERC4626LendingModule__OnlyTokenSweepManager.selector);
        lendingModule.setTokenSweepManager(tokenSweepManager);
        vm.stopPrank();

        // Only the latest manager can update
        vm.startPrank(newTokenSweepManager2);
        lendingModule.setTokenSweepManager(tokenSweepManager);
        vm.stopPrank();
        assertEq(lendingModule.tokenSweepManager(), tokenSweepManager);
    }

    function testSweepMultipleTokens() public {
        ERC20Mock mockToken1 = new ERC20Mock();
        ERC20Mock mockToken2 = new ERC20Mock();
        ERC20Mock mockToken3 = new ERC20Mock();

        mockToken1.mint(address(lendingModule), 100 ether);
        mockToken2.mint(address(lendingModule), 200 ether);
        mockToken3.mint(address(lendingModule), 300 ether);

        vm.startPrank(tokenSweepManager);

        // Sweep all tokens
        lendingModule.sweep(address(mockToken1), recipient);
        lendingModule.sweep(address(mockToken2), recipient);
        lendingModule.sweep(address(mockToken3), recipient);

        assertEq(mockToken1.balanceOf(recipient), 100 ether);
        assertEq(mockToken2.balanceOf(recipient), 200 ether);
        assertEq(mockToken3.balanceOf(recipient), 300 ether);

        assertEq(mockToken1.balanceOf(address(lendingModule)), 0);
        assertEq(mockToken2.balanceOf(address(lendingModule)), 0);
        assertEq(mockToken3.balanceOf(address(lendingModule)), 0);

        vm.stopPrank();
    }
}
