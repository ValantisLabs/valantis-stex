// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {ProtocolFactory} from "@valantis-core/protocol-factory/ProtocolFactory.sol";
import {SovereignPoolFactory} from "@valantis-core/pools/factories/SovereignPoolFactory.sol";
import {ISovereignPool} from "@valantis-core/pools/interfaces/ISovereignPool.sol";
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

        withdrawalModule = new WithdrawalModule(address(overseer), address(this));

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
    }

    function testDeploy() public {
        WithdrawalModule withdrawalModuleDeployment = new WithdrawalModule(address(overseer), address(this));
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
        assertEq(hammDeployment.withdrawalModule(), address(withdrawalModuleDeployment));

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

    function _setSwapFeeParams(uint128 reserve1Target, uint32 feeMinBips, uint32 feeMaxBips) private {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        hamm.setSwapFeeParams(reserve1Target, feeMinBips, feeMaxBips);

        vm.startPrank(owner);

        vm.expectRevert(HAMM.HAMM__setSwapFeeParams_invalidFeeMin.selector);
        hamm.setSwapFeeParams(reserve1Target, 5_000, feeMaxBips);

        vm.expectRevert(HAMM.HAMM__setSwapFeeParams_invalidFeeMax.selector);
        hamm.setSwapFeeParams(reserve1Target, feeMinBips, 5_000);

        vm.expectRevert(HAMM.HAMM__setSwapFeeParams_inconsistentFeeParams.selector);
        hamm.setSwapFeeParams(reserve1Target, 2, 1);

        hamm.setSwapFeeParams(reserve1Target, feeMinBips, feeMaxBips);

        (uint128 reserveTarget, uint32 feeMin, uint32 feeMax) = hamm.feeParams();
        assertEq(reserveTarget, reserve1Target);
        assertEq(feeMin, feeMinBips);
        assertEq(feeMax, feeMaxBips);

        vm.stopPrank();
    }
}
