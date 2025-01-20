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
import {WithdrawalModule} from "src/WithdrawalModule.sol";
import {MockOverseer} from "src/mocks/MockOverseer.sol";
import {FeeParams} from "src/structs/HAMMStructs.sol";

contract HAMMTest is Test {
    HAMM hamm;
    WithdrawalModule withdrawalModule;

    ProtocolFactory protocolFactory;

    WETH weth;
    ERC20Mock token0;

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

        withdrawalModule = new WithdrawalModule(
            address(overseer),
            address(this)
        );

        token0 = new ERC20Mock();
        weth = new WETH();

        hamm = new HAMM(
            address(token0),
            address(weth),
            address(protocolFactory),
            poolFeeRecipient1,
            poolFeeRecipient2,
            owner,
            address(withdrawalModule)
        );
        withdrawalModule.setHAMM(address(hamm));

        pool = ISovereignPool(hamm.pool());

        vm.deal(address(this), 200 ether);
        weth.deposit{value: 100 ether}();
    }

    function testDeploy() public {
        WithdrawalModule withdrawalModuleDeployment = new WithdrawalModule(
            address(overseer),
            address(this)
        );
        assertEq(withdrawalModuleDeployment.overseer(), address(overseer));
        assertEq(withdrawalModuleDeployment.initializer(), address(this));
        assertEq(withdrawalModuleDeployment.hamm(), address(0));

        HAMM hammDeployment = new HAMM(
            address(token0),
            address(weth),
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
        assertEq(
            hammDeployment.withdrawalModule(),
            address(withdrawalModuleDeployment)
        );

        ISovereignPool poolDeployment = ISovereignPool(hammDeployment.pool());
        assertEq(poolDeployment.token0(), address(token0));
        assertEq(poolDeployment.token1(), address(weth));
        assertEq(poolDeployment.alm(), address(hammDeployment));
        assertEq(poolDeployment.swapFeeModule(), address(hammDeployment));
        assertEq(poolDeployment.poolManager(), address(hammDeployment));
    }

    function testSwapSwapFeeParams() public {
        _setSwapFeeParams(100 ether, 1, 20);
    }

    function _setSwapFeeParams(
        uint128 reserve1Target,
        uint32 feeMinBips,
        uint32 feeMaxBips
    ) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                address(this)
            )
        );
        hamm.setSwapFeeParams(reserve1Target, feeMinBips, feeMaxBips);

        vm.startPrank(owner);

        vm.expectRevert(HAMM.HAMM__setSwapFeeParams_invalidFeeMin.selector);
        hamm.setSwapFeeParams(reserve1Target, 5_000, feeMaxBips);

        vm.expectRevert(HAMM.HAMM__setSwapFeeParams_invalidFeeMax.selector);
        hamm.setSwapFeeParams(reserve1Target, feeMinBips, 5_000);

        vm.expectRevert(
            HAMM.HAMM__setSwapFeeParams_inconsistentFeeParams.selector
        );
        hamm.setSwapFeeParams(reserve1Target, 2, 1);

        hamm.setSwapFeeParams(reserve1Target, feeMinBips, feeMaxBips);

        (uint128 reserveTarget, uint32 feeMin, uint32 feeMax) = hamm
            .feeParams();
        assertEq(reserveTarget, reserve1Target);
        assertEq(feeMin, feeMinBips);
        assertEq(feeMax, feeMaxBips);

        vm.stopPrank();
    }

    function testSwapPoolManagerFeeBips() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                address(this)
            )
        );
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
        ALMLiquidityQuoteInput memory input;
        input.amountInMinusFee = 123e18;
        ALMLiquidityQuote memory quote = hamm.getLiquidityQuote(
            input,
            new bytes(0),
            new bytes(0)
        );
        assertEq(quote.amountInFilled, input.amountInMinusFee);
        assertEq(quote.amountOut, input.amountInMinusFee);
    }

    function testOnSwapCallback() public {
        vm.expectRevert(HAMM.HAMM__onSwapCallback_NotImplemented.selector);
        hamm.onSwapCallback(false, 0, 0);
    }
}
