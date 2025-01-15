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
    address deployer;
    address submitter;
    address[] initialParticipants;
    address[] handlers;

    function setUp() public {
        // TODO: temporary dao contract
        daoContract = vm.envAddress("DAO_CONTRACT_ADDR");
        console.log("DAO contract addr: ", daoContract);
        tssSigner = vm.envAddress("TSS_SIGNER_ADDR");
        console.log("TSS signer addr: ", tssSigner);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.createWallet(deployerPrivateKey).addr;
        console.log("Deployer address: ", deployer);

        vm.startBroadcast(deployerPrivateKey);

        setupParticipant(true);
        deploy(true);

        vm.stopBroadcast();
    }

    function setupParticipant(bool _fromEnv) public {
        if (_fromEnv) {
            submitter = vm.envAddress("PARTICIPANT_1");
            initialParticipants.push(submitter);
            initialParticipants.push(submitter);
            initialParticipants.push(submitter);
            console.log("\nSubmitter: ", submitter);
        } else {
            (address participant1, uint256 key1) = makeAddrAndKey("participant1");
            initialParticipants.push(participant1);
            initialParticipants.push(participant1);
            initialParticipants.push(participant1);
            console.log("\nSubmitter: ", participant1);
            console.logBytes32(bytes32(key1));
            submitter = participant1;
        }
    }

    function deploy(bool _useEntryPoint) public {
        address entryPointAddr;
        if (_useEntryPoint) {
            // deploy entryPoint proxy
            EntryPointUpgradeable entryPoint = new EntryPointUpgradeable();
            entryPointAddr = address(entryPoint);
            console.log("\n  |EntryPoint| ", entryPointAddr);
        } else {
            entryPointAddr = submitter;
        }

        MockNuvoToken nuvoToken = new MockNuvoToken();
        console.log("|NuvoToken|", address(nuvoToken));

        // deploy nuvoLock
        NuvoLockUpgradeable nuvoLock = new NuvoLockUpgradeable(address(nuvoToken));
        nuvoLock.initialize(deployer, daoContract, entryPointAddr, 300, 10);
        console.log("|NuvoLock|", address(nuvoLock));

        // deploy taskManager
        TaskManagerUpgradeable taskManager = new TaskManagerUpgradeable();
        console.log("|TaskManager|", address(taskManager));

        // deploy participantHandler
        ParticipantHandlerUpgradeable participantHandler = new ParticipantHandlerUpgradeable(
            address(nuvoLock),
            address(taskManager)
        );
        participantHandler.initialize(daoContract, entryPointAddr, submitter, initialParticipants);
        handlers.push(address(participantHandler));
        console.log("|ParticipantHandler|", address(participantHandler));

        // deploy accountHandler
        AccountHandlerUpgradeable accountHandler = new AccountHandlerUpgradeable(
            address(taskManager)
        );
        accountHandler.initialize(daoContract, entryPointAddr, submitter);
        handlers.push(address(accountHandler));
        console.log("|AccountHandler|", address(accountHandler));

        // deploy accountHandler
        AssetHandlerUpgradeable assetHandler = new AssetHandlerUpgradeable(address(taskManager));
        assetHandler.initialize(daoContract, entryPointAddr, submitter);
        handlers.push(address(assetHandler));
        console.log("|AssetHandler|", address(assetHandler));

        // deploy fundsHandler
        FundsHandlerUpgradeable fundsHandler = new FundsHandlerUpgradeable(
            address(assetHandler),
            address(taskManager)
        );
        fundsHandler.initialize(daoContract, entryPointAddr, submitter);
        handlers.push(address(fundsHandler));
        console.log("|FundsHandler|", address(fundsHandler));

        // initialize entryPoint link to all contracts
        taskManager.initialize(daoContract, entryPointAddr, handlers);
        if (_useEntryPoint) {
            EntryPointUpgradeable entryPoint = EntryPointUpgradeable(entryPointAddr);
            entryPoint.initialize(
                tssSigner, // tssSigner
                address(participantHandler), // participantHandler
                address(taskManager), // taskManager
                address(nuvoLock) // nuvoLock
            );
        }
    }
}
