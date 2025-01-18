// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MockNuvoToken} from "../src/mocks/MockNuvoToken.sol";
import {NuvoLockUpgradeable} from "../src/NuvoLockUpgradeable.sol";

// this contract is only used for contract testing
contract ParticipantSetup is Script {
    MockNuvoToken nuvoToken;
    NuvoLockUpgradeable nuvoLock;

    function setUp() public {
        nuvoToken = MockNuvoToken(vm.envAddress("NUVO_TOKEN_ADDR"));
        nuvoLock = NuvoLockUpgradeable(vm.envAddress("NUVO_LOCK_ADDR"));
        console.log("nuvoToken: ", address(nuvoToken));
        console.log("nuvoLock: ", address(nuvoLock));
    }

    function run() public {
        uint256 privKey1 = vm.envUint("PARTICIPANT_KEY_1");
        address participant1 = vm.createWallet(privKey1).addr;
        console.log("participant1 address: ", participant1);
        vm.startBroadcast(privKey1);
        nuvoToken.mint(participant1, 10 ether);
        nuvoToken.approve(address(nuvoLock), 1 ether);
        nuvoLock.lock(1 ether, 300);
        vm.stopBroadcast();

        uint256 privKey2 = vm.envUint("PARTICIPANT_KEY_2");
        address participant2 = vm.createWallet(privKey2).addr;
        console.log("participant2 address: ", participant2);
        vm.startBroadcast(privKey2);
        nuvoToken.mint(participant2, 10 ether);
        nuvoToken.approve(address(nuvoLock), 1 ether);
        nuvoLock.lock(1 ether, 300);
        vm.stopBroadcast();

        uint256 privKey3 = vm.envUint("PARTICIPANT_KEY_3");
        address participant3 = vm.createWallet(privKey3).addr;
        console.log("participant3 address: ", participant3);
        vm.startBroadcast(privKey3);
        nuvoToken.mint(participant3, 10 ether);
        nuvoToken.approve(address(nuvoLock), 1 ether);
        nuvoLock.lock(1 ether, 300);
        vm.stopBroadcast();
    }
}
