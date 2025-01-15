// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {AccountHandlerUpgradeable} from "../src/handlers/AccountHandlerUpgradeable.sol";
import {AssetHandlerUpgradeable} from "../src/handlers/AssetHandlerUpgradeable.sol";
import {FundsHandlerUpgradeable} from "../src/handlers/FundsHandlerUpgradeable.sol";
import {NuvoLockUpgradeable} from "../src/NuvoLockUpgradeable.sol";
import {TaskManagerUpgradeable} from "../src/TaskManagerUpgradeable.sol";
import {ParticipantHandlerUpgradeable} from "../src/handlers/ParticipantHandlerUpgradeable.sol";
import {EntryPointUpgradeable} from "../src/EntryPointUpgradeable.sol";

contract Deploy is Script {
    address nuvoToken;
    address daoContract;
    address tssSigner;
    address[] initialParticipants;

    address[] handlers;
    address vmProxy;
    address lockProxy;
    address pmProxy;
    address tmProxy;
    address amProxy;
    address ahProxy;
    address dmProxy;
    address nip20Proxy;

    function setUp() public {
        // TODO: temporary dao contract
        daoContract = vm.envAddress("DAO_CONTRACT_ADDR");
        console.log("DAO contract addr: ", daoContract);
        nuvoToken = vm.envAddress("NUVO_TOKEN_ADDR");
        tssSigner = vm.envAddress("TSS_SIGNER_ADDR");
        initialParticipants.push(vm.envAddress("PARTICIPANT_1"));
        initialParticipants.push(vm.envAddress("PARTICIPANT_2"));
        initialParticipants.push(vm.envAddress("PARTICIPANT_3"));
    }

    function run() public {
        require(initialParticipants.length > 2, "Require at least 3 participant");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.createWallet(deployerPrivateKey).addr;
        console.log("Deployer address: ", deployer);
        vm.startBroadcast(deployerPrivateKey);

        // deploy entryPoint proxy
        vmProxy = deployProxy(address(new EntryPointUpgradeable()), daoContract);

        // deploy nuvoLock
        lockProxy = deployProxy(address(new NuvoLockUpgradeable(nuvoToken)), daoContract);
        NuvoLockUpgradeable nuvoLock = NuvoLockUpgradeable(lockProxy);
        nuvoLock.initialize(deployer, daoContract, vmProxy, 1 weeks, 1 ether);

        // deploy taskManager & taskSubmitter
        tmProxy = deployProxy(address(new TaskManagerUpgradeable()), daoContract);
        TaskManagerUpgradeable taskManager = TaskManagerUpgradeable(tmProxy);

        // deploy participantHandler
        pmProxy = deployProxy(
            address(new ParticipantHandlerUpgradeable(lockProxy, tmProxy)),
            daoContract
        );
        ParticipantHandlerUpgradeable participantHandler = ParticipantHandlerUpgradeable(pmProxy);
        participantHandler.initialize(daoContract, vmProxy, deployer, initialParticipants);
        handlers.push(pmProxy);

        // deploy assetHandler
        ahProxy = deployProxy(address(new AssetHandlerUpgradeable(tmProxy)), daoContract);
        AssetHandlerUpgradeable assetHandler = AssetHandlerUpgradeable(ahProxy);
        assetHandler.initialize(daoContract, vmProxy, deployer);
        handlers.push(ahProxy);

        // deploy accountHandler
        amProxy = deployProxy(address(new AccountHandlerUpgradeable(tmProxy)), daoContract);
        AccountHandlerUpgradeable accountHandler = AccountHandlerUpgradeable(amProxy);
        accountHandler.initialize(daoContract, vmProxy, deployer);
        handlers.push(amProxy);

        // deploy fundsHandler
        dmProxy = deployProxy(address(new FundsHandlerUpgradeable(ahProxy, tmProxy)), daoContract);
        FundsHandlerUpgradeable fundsHandler = FundsHandlerUpgradeable(dmProxy);
        fundsHandler.initialize(daoContract, vmProxy, deployer);
        handlers.push(dmProxy);

        // initialize entryPoint link to all contracts
        taskManager.initialize(daoContract, vmProxy, handlers);
        EntryPointUpgradeable entryPoint = EntryPointUpgradeable(vmProxy);
        entryPoint.initialize(
            tssSigner, // tssSigner
            pmProxy, // participantHandler
            tmProxy, // taskManager
            lockProxy // nuvoLock
        );

        vm.stopBroadcast();
    }

    function deployProxy(address _logic, address _admin) internal returns (address) {
        return address(new TransparentUpgradeableProxy(_logic, _admin, ""));
    }
}
