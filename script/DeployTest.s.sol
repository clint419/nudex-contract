// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

import {MockNuvoToken} from "../src/mocks/MockNuvoToken.sol";

import {AccountHandlerUpgradeable} from "../src/handlers/AccountHandlerUpgradeable.sol";
import {AssetHandlerUpgradeable} from "../src/handlers/AssetHandlerUpgradeable.sol";
import {FundsHandlerUpgradeable} from "../src/handlers/FundsHandlerUpgradeable.sol";
import {NuvoLockUpgradeable} from "../src/NuvoLockUpgradeable.sol";
import {TaskManagerUpgradeable} from "../src/TaskManagerUpgradeable.sol";
import {ParticipantHandlerUpgradeable} from "../src/handlers/ParticipantHandlerUpgradeable.sol";
import {EntryPointUpgradeable} from "../src/EntryPointUpgradeable.sol";

// this contract is only used for contract testing
contract DeployTest is Script {
    address daoContract;
    address tssSigner;
    address[] initialParticipants;
    address[] handlers;

    function setUp() public {
        // TODO: temporary dao contract
        daoContract = vm.envAddress("DAO_CONTRACT_ADDR");
        console.log("DAO contract addr: ", daoContract);

        tssSigner = vm.envAddress("TSS_SIGNER_ADDR");
        initialParticipants.push(vm.envAddress("PARTICIPANT_1"));
        initialParticipants.push(vm.envAddress("PARTICIPANT_1"));
        initialParticipants.push(vm.envAddress("PARTICIPANT_1"));
    }

    function run() public {
        run(false);
    }

    function run(bool _useEntryPoint) public {
        uint256 deployerPrivateKey = vm.envUint("PARTICIPANT_KEY_1");
        address deployer = vm.envAddress("PARTICIPANT_1");
        console.log("Deployer address: ", deployer);
        vm.startBroadcast(deployerPrivateKey);

        address entryPointAddr;
        if (_useEntryPoint) {
            // deploy entryPoint proxy
            EntryPointUpgradeable entryPoint = new EntryPointUpgradeable();
            entryPointAddr = address(entryPoint);
            console.log("|EntryPoint| ", entryPointAddr);
        } else {
            entryPointAddr = deployer;
        }

        MockNuvoToken nuvoToken = new MockNuvoToken();
        console.log("|NuvoToken|", address(nuvoToken));

        // deploy nuvoLock
        NuvoLockUpgradeable nuvoLock = new NuvoLockUpgradeable();
        nuvoLock.initialize(address(nuvoToken), deployer, entryPointAddr, 300, 10);
        console.log("|NuvoLock|", address(nuvoLock));

        // deploy taskManager
        TaskManagerUpgradeable taskManager = new TaskManagerUpgradeable();
        console.log("|TaskManager|", address(taskManager));

        // deploy participantManager
        ParticipantHandlerUpgradeable participantManager = new ParticipantHandlerUpgradeable(
            address(nuvoLock),
            address(taskManager)
        );
        participantManager.initialize(daoContract, entryPointAddr, deployer, initialParticipants);
        handlers.push(address(participantManager));
        console.log("|ParticipantHandler|", address(participantManager));

        // deploy accountManager
        AccountHandlerUpgradeable accountManager = new AccountHandlerUpgradeable(
            address(taskManager)
        );
        accountManager.initialize(daoContract, entryPointAddr, deployer);
        handlers.push(address(accountManager));
        console.log("|AccountHandler|", address(accountManager));

        // deploy accountManager
        AssetHandlerUpgradeable assetHandler = new AssetHandlerUpgradeable(address(taskManager));
        assetHandler.initialize(daoContract, entryPointAddr, deployer);
        handlers.push(address(assetHandler));
        console.log("|AssetHandler|", address(assetHandler));

        // deploy depositManager
        FundsHandlerUpgradeable depositManager = new FundsHandlerUpgradeable(
            address(assetHandler),
            address(taskManager)
        );
        depositManager.initialize(daoContract, entryPointAddr, deployer);
        handlers.push(address(depositManager));
        console.log("|FundsHandler|", address(depositManager));

        // initialize entryPoint link to all contracts
        taskManager.initialize(daoContract, entryPointAddr, handlers);
        if (_useEntryPoint) {
            EntryPointUpgradeable entryPoint = EntryPointUpgradeable(entryPointAddr);
            entryPoint.initialize(
                tssSigner, // tssSigner
                address(participantManager), // participantManager
                address(taskManager), // taskManager
                address(nuvoLock) // nuvoLock
            );
        }

        vm.stopBroadcast();
    }
}
