// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {STEXLens} from "src/STEXLens.sol";
import {STEXAMM} from "src/STEXAMM.sol";
import {DepositWrapper} from "src/DepositWrapper.sol";

contract kHYPESTEXLPScript is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        if (block.chainid != 999) revert("Chain Id not HyperEVM mainnet");

        console.log("Deployer address: ", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        STEXLens stexLens = STEXLens(
            0x95e88072c3fe908101a13584d7A0ff87DaDd88f3
        );
        STEXAMM stex = STEXAMM(
            payable(0xbf747D2959F03332dbd25249dB6f00F62c6Cb526)
        );

        // Uncomment for deposits
        /*uint256 amount = 0.01 ether;
        uint256 shares = stexLens.getSharesForDeposit(address(stex), amount);

        DepositWrapper depositWrapper = DepositWrapper(
            payable(0xA2918c869e352ADdd5b1f9f12cDe5672B23f139d)
        );
        uint256 sharesDeposited = depositWrapper.depositFromNative{
            value: amount
        }((shares * 9999) / 10_000, block.timestamp + 120, deployerAddress);

        console.log("shares expected: ", shares);
        console.log("shares deposited: ", sharesDeposited);
        console.log(
            "native token balance after deposit: ",
            deployerAddress.balance
        );*/

        // Uncomment for withdrawals
        /*uint256 amount = stex.balanceOf(deployerAddress);
        bool isInstantWithdrawal = true;

        (uint256 amount0, uint256 amount1) = stexLens.getAmountsForWithdraw(
            address(stex),
            amount,
            isInstantWithdrawal
        );

        console.log("amount0 expected: ", amount0);
        console.log("amount1 expected: ", amount1);

        (uint256 amount0Withdraw, uint256 amount1Withdraw) = stex.withdraw(
            amount,
            amount0,
            amount1,
            block.timestamp + 120,
            deployerAddress,
            true,
            isInstantWithdrawal
        );

        console.log("amount0 withdraw: ", amount0Withdraw);
        console.log("amount1 withdraw: ", amount1Withdraw);*/

        vm.stopBroadcast();
    }
}
