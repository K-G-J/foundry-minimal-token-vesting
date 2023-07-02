// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {Vesting} from "../src/Vesting.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployVesting is Script {
    function run() public returns (Vesting vesting, ERC20Mock token) {
        token = new ERC20Mock();
        vm.startBroadcast();
        vesting = new Vesting(IERC20(token));
        vm.stopBroadcast();

        return (vesting, token);
    }
}
