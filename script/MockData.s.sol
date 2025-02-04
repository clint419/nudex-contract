// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {NuvoProxy, ITransparentUpgradeableProxy} from "../src/proxies/NuvoProxy.sol";
import {AccountHandlerUpgradeable} from "../src/handlers/AccountHandlerUpgradeable.sol";
import {AssetHandlerUpgradeable, AssetParam, TokenInfo, ConsolidateTaskParam} from "../src/handlers/AssetHandlerUpgradeable.sol";
import {FundsHandlerUpgradeable, DepositInfo, WithdrawalInfo} from "../src/handlers/FundsHandlerUpgradeable.sol";
import {TaskManagerUpgradeable, State} from "../src/TaskManagerUpgradeable.sol";
import {IAccountHandler, AddressCategory} from "../src/interfaces/IAccountHandler.sol";

// this contract is only used for contract testing
contract MockData is Script {
    uint64 public constant CHAIN_ID = 0;
    bytes32 public constant TICKER = "TOKEN_TICKER_18";
    bytes32 public constant FUNDS_ROLE = keccak256("FUNDS_ROLE");

    uint256 public deployerPrivateKey;
    address public deployer;

    TaskManagerUpgradeable taskManager;
    AccountHandlerUpgradeable accountHandler;
    AssetHandlerUpgradeable assetHandler;
    FundsHandlerUpgradeable fundsHandler;

    address[] public handlers;

    function setUp() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.createWallet(deployerPrivateKey).addr;

        vm.startBroadcast(deployerPrivateKey);
        _setupContracts(true);
        vm.stopBroadcast();
    }

    function _setupContracts(bool _fromEnv) internal {
        if (_fromEnv) {
            taskManager = TaskManagerUpgradeable(vm.envAddress("TASK_MANAGER"));
            accountHandler = AccountHandlerUpgradeable(vm.envAddress("ACCOUNT_HANDLER"));
            assetHandler = AssetHandlerUpgradeable(vm.envAddress("ASSET_HANDLER"));
            fundsHandler = FundsHandlerUpgradeable(vm.envAddress("FUNDS_HANDLER"));
        } else {
            taskManager = new TaskManagerUpgradeable();
            console.log("|TaskManager|", address(taskManager));

            // deploy accountHandler
            accountHandler = new AccountHandlerUpgradeable(address(taskManager));
            // NuvoProxy proxy = new NuvoProxy(address(accountHandler), vm.envAddress("PARTICIPANT_2"));
            // accountHandler = AccountHandlerUpgradeable(address(proxy));
            accountHandler.initialize(deployer, deployer, deployer);
            handlers.push(address(accountHandler));
            console.log("|AccountHandler|", address(accountHandler));

            // deploy assetHandler
            assetHandler = new AssetHandlerUpgradeable(address(taskManager));
            // proxy = new NuvoProxy(address(assetHandler), vm.envAddress("PARTICIPANT_2"));
            // assetHandler = AssetHandlerUpgradeable(address(proxy));
            assetHandler.initialize(deployer, deployer, deployer);
            handlers.push(address(assetHandler));
            console.log("|AssetHandlerUpgradeable|", address(assetHandler));

            // deploy fundsHandler
            fundsHandler = new FundsHandlerUpgradeable(address(assetHandler), address(taskManager));
            // proxy = new NuvoProxy(address(fundsHandler), vm.envAddress("PARTICIPANT_2"));
            // fundsHandler = FundsHandlerUpgradeable(address(proxy));
            fundsHandler.initialize(deployer, deployer, deployer);
            handlers.push(address(fundsHandler));
            assetHandler.grantRole(FUNDS_ROLE, address(fundsHandler));
            console.log("|FundsHandlerUpgradeable|", address(fundsHandler));

            taskManager.initialize(deployer, deployer, handlers);
            console.log("Deployer address: ", deployer);
        }
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // assetData();
        fundsData(0x4e554445585f555344435f313800000000000000000000000000000000000000, 59902);
        // accountData();
        // updateTask();

        vm.stopBroadcast();
    }

    function assetData() public {
        // asset
        AssetParam memory assetParam = AssetParam(18, true, true, 1 ether, 1 ether, "Token_Alias");
        assetHandler.listNewAsset(TICKER, assetParam);
        TokenInfo[] memory testTokenInfo = new TokenInfo[](1);
        testTokenInfo[0] = TokenInfo(CHAIN_ID, true, uint8(18), "0xContractAddress", "SYMBOL", 0);
        assetHandler.linkToken(TICKER, testTokenInfo);

        // consolidate
        ConsolidateTaskParam[] memory consolidateTaskParams = new ConsolidateTaskParam[](3);
        consolidateTaskParams[0] = ConsolidateTaskParam(
            "fromAddr1",
            TICKER,
            CHAIN_ID,
            1 ether,
            bytes32(uint256(0))
        );
        consolidateTaskParams[1] = ConsolidateTaskParam(
            "fromAddr2",
            TICKER,
            CHAIN_ID,
            2.5 ether,
            bytes32(uint256(1))
        );
        consolidateTaskParams[2] = ConsolidateTaskParam(
            "fromAddr3",
            TICKER,
            CHAIN_ID,
            3.3 ether,
            bytes32(uint256(2))
        );
        assetHandler.submitConsolidateTask(consolidateTaskParams);
        assetHandler.consolidate(
            "fromAddr1",
            TICKER,
            CHAIN_ID,
            1 ether,
            bytes32(uint256(0)),
            "consolidate txHash1"
        );
        assetHandler.consolidate(
            "fromAddr2",
            TICKER,
            CHAIN_ID,
            2.5 ether,
            bytes32(uint256(1)),
            "consolidate txHash2"
        );
        assetHandler.consolidate(
            "fromAddr3",
            TICKER,
            CHAIN_ID,
            3.3 ether,
            bytes32(uint256(2)),
            "consolidate txHash3"
        );

        assetHandler.tokenSwitch(TICKER, CHAIN_ID, false);
        assetHandler.tokenSwitch(TICKER, CHAIN_ID, true);
    }

    function fundsData(bytes32 _ticker, uint64 _chainId) public {
        // deposit
        DepositInfo[] memory depositInfos = new DepositInfo[](1);
        depositInfos[0] = DepositInfo(
            deployer,
            _chainId,
            _ticker,
            "124wd5urvxo4H3naXR6QACP1MGVpLeikeR",
            1 ether,
            "txHash",
            0,
            0
        );
        fundsHandler.submitDepositTask(depositInfos);
        // fundsHandler.recordDeposit(depositInfos[0]);

        // withdraw
        WithdrawalInfo[] memory withdrawalInfos = new WithdrawalInfo[](1);
        withdrawalInfos[0] = WithdrawalInfo(
            deployer,
            _chainId,
            _ticker,
            "124wd5urvxo4H3naXR6QACP1MGVpLeikeR",
            1 ether,
            bytes32(uint256(0))
        );

        fundsHandler.submitWithdrawTask(withdrawalInfos);
        // fundsHandler.recordWithdrawal(
        //     deployer,
        //     _chainId,
        //     _ticker,
        //     "124wd5urvxo4H3naXR6QACP1MGVpLeikeR",
        //     1 ether,
        //     "TxHash"
        // );
        // fundsHandler.setPauseState(_ticker, false);
        // fundsHandler.setPauseState(bytes32(uint256(_chainId)), false);
    }

    function accountData() public {
        for (uint8 i; i < 5; ++i) {
            accountHandler.registerNewAddress(
                deployer,
                10001 + i,
                AddressCategory.EVM,
                i,
                Strings.toHexString(makeAddr(Strings.toString(i)))
            );
        }

        accountHandler.registerNewAddress(
            deployer,
            10001,
            AddressCategory.BTC,
            0,
            "124wd5urvxo4H3naXR6QACP1MGVpLeikeR"
        );
        accountHandler.registerNewAddress(
            deployer,
            10002,
            AddressCategory.BTC,
            1,
            "1HkJEUpgptueutWRFB1bjHGKA5wtKBoToW"
        );
        accountHandler.registerNewAddress(
            deployer,
            10003,
            AddressCategory.BTC,
            2,
            "1PS21zbYxJZUzsHg91MfxUDbqkn7BEw2C5"
        );

        accountHandler.registerNewAddress(
            deployer,
            10001,
            AddressCategory.SOL,
            0,
            "w9A6215VdjCgX9BVwK1ZXE7sKBuNGh7bdmeGBEs7625"
        );
        accountHandler.registerNewAddress(
            deployer,
            10002,
            AddressCategory.SOL,
            1,
            "4WMARsRWo8x7oJRwTQ9LhbDuiAnzz5TF3WzpTCgACrfe"
        );
        accountHandler.registerNewAddress(
            deployer,
            10003,
            AddressCategory.SOL,
            2,
            "8ymc6niJiF4imco29UU3z7mK11sCt9NdL3LjG3VkEYAC"
        );
    }

    function updateTask() public {
        taskManager.updateTask(0, State.Completed);
        taskManager.updateTask(1, State.Pending);
        taskManager.updateTask(2, State.Failed);
    }
}
