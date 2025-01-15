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
        deploy(
            address(0xD7Bf3503C856c18eCb07eAf72E45E37f9Ab68A5B),
            address(0xba7E53478Cb713d1eb46C1170F7c85bbd2BFc6Df),
            address(0xc8006AAD20e8D15C7B3F8b45f309864034b9156B)
        );

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

    function deploy(address _entryPoint, address _nuvoToken, address _nuvoLock) public {
        address entryPointAddr;
        if (_entryPoint == address(0)) {
            // deploy entryPoint proxy
            EntryPointUpgradeable entryPoint = new EntryPointUpgradeable();
            entryPointAddr = address(entryPoint);
            console.log("\n  |EntryPoint| ", entryPointAddr);
        } else {
            entryPointAddr = _entryPoint;
        }

        // deploy nuvoToken
        if (_nuvoToken == address(0)) {
            MockNuvoToken nuvoToken = new MockNuvoToken();
            console.log("|NuvoToken|", address(nuvoToken));
            _nuvoToken = address(nuvoToken);
        }

        // deploy nuvoLock
        if (_nuvoLock == address(0)) {
            NuvoLockUpgradeable nuvoLock = new NuvoLockUpgradeable(_nuvoToken);
            nuvoLock.initialize(deployer, daoContract, entryPointAddr, 300, 10);
            console.log("|NuvoLock|", address(nuvoLock));
            _nuvoLock = address(nuvoLock);
        }

        // deploy taskManager
        TaskManagerUpgradeable taskManager = new TaskManagerUpgradeable();
        console.log("|TaskManager|", address(taskManager));

        // deploy participantHandler
        ParticipantHandlerUpgradeable participantHandler = new ParticipantHandlerUpgradeable(
            _nuvoLock,
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
        if (_entryPoint == address(0)) {
            EntryPointUpgradeable entryPoint = EntryPointUpgradeable(entryPointAddr);
            entryPoint.initialize(
                tssSigner, // tssSigner
                address(participantHandler), // participantHandler
                address(taskManager), // taskManager
                _nuvoLock // nuvoLock
            );
        }
    }
}
