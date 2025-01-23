// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {AccountHandlerUpgradeable} from "../src/handlers/AccountHandlerUpgradeable.sol";
import {AssetHandlerUpgradeable} from "../src/handlers/AssetHandlerUpgradeable.sol";
import {FundsHandlerUpgradeable} from "../src/handlers/FundsHandlerUpgradeable.sol";
import {NuvoLockUpgradeable} from "../src/NuvoLockUpgradeable.sol";
import {TaskManagerUpgradeable} from "../src/TaskManagerUpgradeable.sol";
import {ParticipantHandlerUpgradeable} from "../src/handlers/ParticipantHandlerUpgradeable.sol";
import {EntryPointUpgradeable} from "../src/EntryPointUpgradeable.sol";
import {NuvoProxy} from "../src/proxies/NuvoProxy.sol";

contract Deploy is Script {
    address nuvoToken;
    address daoContract;
    address tssSigner;
    address submitter;
    address[] initialParticipants;
    address[] handlers;
    address proxyAdminContract;

    address entryPointProxy;
    address nuvoLockProxy;
    address participantHandlerProxy;
    address taskManagerProxy;
    address accountHandlerProxy;
    address assetHandlerProxy;
    address fundsHandlerProxy;

    function setUp() public {
        // TODO: temporary dao contract
        daoContract = vm.envAddress("DAO_CONTRACT_ADDR");
        console.log("DAO contract addr: ", daoContract);
        nuvoToken = vm.envAddress("NUVO_TOKEN_ADDR");
        tssSigner = vm.envAddress("TSS_SIGNER_ADDR");
        submitter = vm.envAddress("SUBMITTER_ADDR");
        initialParticipants.push(vm.envAddress("PARTICIPANT_1"));
        initialParticipants.push(vm.envAddress("PARTICIPANT_2"));
        initialParticipants.push(vm.envAddress("PARTICIPANT_3"));
        proxyAdminContract = address(new ProxyAdmin(daoContract));

        console.log("Proxy Admin", proxyAdminContract);
        console.log("Submitter", submitter);
        for (uint8 i; i < initialParticipants.length; ++i) {
            console.log("participant", i, " address: ", initialParticipants[i]);
        }
    }

    function run() public {
        require(initialParticipants.length > 2, "Require at least 3 participant");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.createWallet(deployerPrivateKey).addr;
        console.log("Deployer address: ", deployer);

        vm.startBroadcast(deployerPrivateKey);

        deployTopLevel(false);
        deployHandlers(true);

        vm.stopBroadcast();
    }

    function deployTopLevel(bool _fromEnv) public {
        if (_fromEnv) {
            entryPointProxy = vm.envAddress("ENTRY_POINT");
            nuvoLockProxy = vm.envAddress("NUVO_LOCK_ADDR");
        } else {
            // deploy entryPoint
            entryPointProxy = deployProxy(address(new EntryPointUpgradeable()));

            // deploy nuvoLock
            nuvoLockProxy = deployProxy(address(new NuvoLockUpgradeable(nuvoToken)));
            NuvoLockUpgradeable nuvoLock = NuvoLockUpgradeable(nuvoLockProxy);
            nuvoLock.initialize(daoContract, daoContract, entryPointProxy, 1 ether, 1 days);
        }

        console.log("\n  |NuvoToken|", nuvoToken);
        console.log("|EntryPoint| ", entryPointProxy);
        console.log("|NuvoLock|", nuvoLockProxy);
    }

    function deployHandlers(bool _entryPointInit) public {
        // deploy taskManager
        taskManagerProxy = deployProxy(address(new TaskManagerUpgradeable()));
        TaskManagerUpgradeable taskManager = TaskManagerUpgradeable(taskManagerProxy);
        console.log("|TaskManager|", address(taskManager));

        // deploy participantHandler
        participantHandlerProxy = deployProxy(
            address(new ParticipantHandlerUpgradeable(nuvoLockProxy, taskManagerProxy))
        );
        ParticipantHandlerUpgradeable participantHandler = ParticipantHandlerUpgradeable(
            participantHandlerProxy
        );
        participantHandler.initialize(daoContract, entryPointProxy, submitter, initialParticipants);
        handlers.push(participantHandlerProxy);
        handlers.push(address(participantHandler));
        console.log("|ParticipantHandler|", participantHandlerProxy);

        // deploy accountHandler
        accountHandlerProxy = deployProxy(address(new AccountHandlerUpgradeable(taskManagerProxy)));
        AccountHandlerUpgradeable accountHandler = AccountHandlerUpgradeable(accountHandlerProxy);
        accountHandler.initialize(daoContract, entryPointProxy, submitter);
        handlers.push(accountHandlerProxy);
        console.log("|AccountHandler|", accountHandlerProxy);

        // deploy accountHandler
        assetHandlerProxy = deployProxy(address(new AssetHandlerUpgradeable(taskManagerProxy)));
        AssetHandlerUpgradeable assetHandler = AssetHandlerUpgradeable(assetHandlerProxy);
        assetHandler.initialize(daoContract, entryPointProxy, submitter);
        handlers.push(assetHandlerProxy);
        console.log("|AssetHandler|", assetHandlerProxy);

        // deploy fundsHandler
        fundsHandlerProxy = deployProxy(
            address(new FundsHandlerUpgradeable(assetHandlerProxy, taskManagerProxy))
        );
        FundsHandlerUpgradeable fundsHandler = FundsHandlerUpgradeable(fundsHandlerProxy);
        fundsHandler.initialize(daoContract, entryPointProxy, submitter);
        handlers.push(fundsHandlerProxy);
        console.log("|FundsHandler|", fundsHandlerProxy);

        // initialize entryPoint link to all contracts
        taskManager.initialize(daoContract, entryPointProxy, handlers);
        if (_entryPointInit) {
            EntryPointUpgradeable entryPoint = EntryPointUpgradeable(entryPointProxy);
            entryPoint.initialize(
                tssSigner, // tssSigner
                participantHandlerProxy, // participantHandler
                taskManagerProxy, // taskManager
                nuvoLockProxy // nuvoLock
            );
        }
    }

    function deployProxy(address _logic) internal returns (address) {
        return address(new NuvoProxy(_logic, proxyAdminContract));
    }
}
