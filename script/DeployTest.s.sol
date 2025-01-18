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
    EntryPointUpgradeable entryPoint;
    MockNuvoToken nuvoToken;
    NuvoLockUpgradeable nuvoLock;

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
        deployTopLevel(false);
        vm.stopBroadcast();

        setupParticipant(true);

        vm.startBroadcast(deployerPrivateKey);
        deployHandlers(true);
        vm.stopBroadcast();

        console.log("\n   submitter: ", submitter);
        for (uint8 i; i < initialParticipants.length; ++i) {
            console.log("participant", i, " address: ", initialParticipants[i]);
        }
    }

    function deployTopLevel(bool _fromEnv) public {
        if (_fromEnv) {
            entryPoint = EntryPointUpgradeable(vm.envAddress("ENTRY_POINT"));
            nuvoToken = MockNuvoToken(vm.envAddress("NUVO_TOKEN_ADDR"));
            nuvoLock = NuvoLockUpgradeable(vm.envAddress("NUVO_LOCK_ADDR"));
        } else {
            // deploy entryPoint
            entryPoint = new EntryPointUpgradeable();

            // deploy nuvoToken
            nuvoToken = new MockNuvoToken();

            // deploy nuvoLock
            nuvoLock = new NuvoLockUpgradeable(address(nuvoToken));
            nuvoLock.initialize(deployer, daoContract, address(entryPoint), 300, 10);
        }
        console.log("\n  |EntryPoint| ", address(entryPoint));
        console.log("|NuvoToken|", address(nuvoToken));
        console.log("|NuvoLock|", address(nuvoLock));
    }

    function deployHandlers(bool _entryPointInit) public {
        // deploy taskManager
        TaskManagerUpgradeable taskManager = new TaskManagerUpgradeable();
        console.log("|TaskManager|", address(taskManager));

        // deploy participantHandler
        ParticipantHandlerUpgradeable participantHandler = new ParticipantHandlerUpgradeable(
            address(nuvoLock),
            address(taskManager)
        );
        participantHandler.initialize(
            daoContract,
            address(entryPoint),
            submitter,
            initialParticipants
        );
        handlers.push(address(participantHandler));
        console.log("|ParticipantHandler|", address(participantHandler));

        // deploy accountHandler
        AccountHandlerUpgradeable accountHandler = new AccountHandlerUpgradeable(
            address(taskManager)
        );
        accountHandler.initialize(daoContract, address(entryPoint), submitter);
        handlers.push(address(accountHandler));
        console.log("|AccountHandler|", address(accountHandler));

        // deploy accountHandler
        AssetHandlerUpgradeable assetHandler = new AssetHandlerUpgradeable(address(taskManager));
        assetHandler.initialize(daoContract, address(entryPoint), submitter);
        handlers.push(address(assetHandler));
        console.log("|AssetHandler|", address(assetHandler));

        // deploy fundsHandler
        FundsHandlerUpgradeable fundsHandler = new FundsHandlerUpgradeable(
            address(assetHandler),
            address(taskManager)
        );
        fundsHandler.initialize(daoContract, address(entryPoint), submitter);
        handlers.push(address(fundsHandler));
        console.log("|FundsHandler|", address(fundsHandler));

        // initialize entryPoint link to all contracts
        taskManager.initialize(daoContract, address(entryPoint), handlers);
        if (_entryPointInit) {
            entryPoint.initialize(
                tssSigner, // tssSigner
                address(participantHandler), // participantHandler
                address(taskManager), // taskManager
                address(nuvoLock) // nuvoLock
            );
        }
    }

    function setupParticipant(bool _fromEnv) public {
        if (_fromEnv) {
            uint256 privKey1 = vm.envUint("PARTICIPANT_KEY_1");
            address participant1 = vm.createWallet(privKey1).addr;
            vm.startBroadcast(privKey1);
            nuvoToken.mint(participant1, 10 ether);
            nuvoToken.approve(address(nuvoLock), 1 ether);
            nuvoLock.lock(1 ether, 300);
            vm.stopBroadcast();

            uint256 privKey2 = vm.envUint("PARTICIPANT_KEY_2");
            address participant2 = vm.createWallet(privKey2).addr;
            vm.startBroadcast(privKey2);
            nuvoToken.mint(participant2, 10 ether);
            nuvoToken.approve(address(nuvoLock), 1 ether);
            nuvoLock.lock(1 ether, 300);
            vm.stopBroadcast();

            uint256 privKey3 = vm.envUint("PARTICIPANT_KEY_3");
            address participant3 = vm.createWallet(privKey3).addr;
            vm.startBroadcast(privKey3);
            nuvoToken.mint(participant3, 10 ether);
            nuvoToken.approve(address(nuvoLock), 1 ether);
            nuvoLock.lock(1 ether, 300);
            vm.stopBroadcast();

            submitter = vm.envAddress("SUBMITTER_ADDR");
            initialParticipants.push(participant1);
            initialParticipants.push(participant2);
            initialParticipants.push(participant3);
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
}
