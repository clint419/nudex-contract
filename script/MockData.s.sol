// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {NuvoProxy, ITransparentUpgradeableProxy} from "../src/proxies/NuvoProxy.sol";
import {AccountHandlerUpgradeable} from "../src/handlers/AccountHandlerUpgradeable.sol";
import {AssetHandlerUpgradeable, AssetParam, TokenInfo, ConsolidateTaskParam} from "../src/handlers/AssetHandlerUpgradeable.sol";
import {FundsHandlerUpgradeable, DepositInfo, WithdrawalInfo} from "../src/handlers/FundsHandlerUpgradeable.sol";
import {TaskManagerUpgradeable, State} from "../src/TaskManagerUpgradeable.sol";
import {IAccountHandler} from "../src/interfaces/IAccountHandler.sol";

// this contract is only used for contract testing
contract MockData is Script {
    uint64 public constant CHAIN_ID = 0;
    bytes32 public constant TICKER = "TOKEN_TICKER_18";
    bytes32 public constant FUNDS_ROLE = keccak256("FUNDS_ROLE");

    uint256 public deployerPrivateKey;
    address public deployer;

    TaskManagerUpgradeable taskManager;
    AccountHandlerUpgradeable accountManager;
    AssetHandlerUpgradeable assetHandler;
    FundsHandlerUpgradeable fundsHandler;

    address[] public handlers;

    function setUp() public {
        deployerPrivateKey = vm.envUint("PARTICIPANT_KEY_1");
        deployer = vm.createWallet(deployerPrivateKey).addr;

        vm.startBroadcast(deployerPrivateKey);

        taskManager = new TaskManagerUpgradeable();
        console.log("|TaskManager|", address(taskManager));

        // deploy accountManager
        accountManager = new AccountHandlerUpgradeable(address(taskManager));
        // NuvoProxy proxy = new NuvoProxy(address(accountManager), vm.envAddress("PARTICIPANT_2"));
        // accountManager = AccountHandlerUpgradeable(address(proxy));
        accountManager.initialize(deployer, deployer, deployer);
        handlers.push(address(accountManager));
        console.log("|AccountHandler|", address(accountManager));

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

        vm.stopBroadcast();
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        assetData();
        accountData();
        fundsData();
        updateTask();
        vm.stopBroadcast();
    }

    function assetData() public {
        // asset
        AssetParam memory assetParam = AssetParam(18, true, true, 1 ether, 1 ether, "Token_Alias");
        assetHandler.submitListAssetTask(TICKER, assetParam);
        assetHandler.listNewAsset(TICKER, assetParam);
        TokenInfo[] memory testTokenInfo = new TokenInfo[](1);
        testTokenInfo[0] = TokenInfo(CHAIN_ID, true, uint8(18), "0xContractAddress", "SYMBOL", 0);
        assetHandler.submitAssetTask(
            TICKER,
            abi.encodeWithSelector(assetHandler.linkToken.selector, TICKER, testTokenInfo)
        );
        assetHandler.linkToken(TICKER, testTokenInfo);

        // consolidate
        ConsolidateTaskParam[] memory consolidateTaskParams = new ConsolidateTaskParam[](3);
        consolidateTaskParams[0] = ConsolidateTaskParam("fromAddr1", TICKER, CHAIN_ID, 1 ether);
        consolidateTaskParams[1] = ConsolidateTaskParam("fromAddr2", TICKER, CHAIN_ID, 2.5 ether);
        consolidateTaskParams[2] = ConsolidateTaskParam("fromAddr3", TICKER, CHAIN_ID, 3.3 ether);
        assetHandler.submitConsolidateTask(consolidateTaskParams);
        assetHandler.consolidate("fromAddr1", TICKER, CHAIN_ID, 1 ether, "consolidate txHash1");
        assetHandler.consolidate("fromAddr2", TICKER, CHAIN_ID, 2.5 ether, "consolidate txHash2");
        assetHandler.consolidate("fromAddr3", TICKER, CHAIN_ID, 3.3 ether, "consolidate txHash3");

        assetHandler.tokenSwitch(TICKER, CHAIN_ID, false);
        assetHandler.tokenSwitch(TICKER, CHAIN_ID, true);
    }

    function fundsData() public {
        // deposit
        DepositInfo[] memory depositInfos = new DepositInfo[](1);
        depositInfos[0] = DepositInfo(
            deployer,
            CHAIN_ID,
            TICKER,
            "124wd5urvxo4H3naXR6QACP1MGVpLeikeR",
            1 ether,
            "txHash",
            0,
            0
        );
        fundsHandler.submitDepositTask(depositInfos);
        fundsHandler.recordDeposit(depositInfos[0]);

        // withdraw
        WithdrawalInfo[] memory withdrawalInfos = new WithdrawalInfo[](1);
        withdrawalInfos[0] = WithdrawalInfo(
            deployer,
            CHAIN_ID,
            TICKER,
            "124wd5urvxo4H3naXR6QACP1MGVpLeikeR",
            1 ether
        );

        fundsHandler.submitWithdrawTask(withdrawalInfos);
        fundsHandler.recordWithdrawal(
            deployer,
            CHAIN_ID,
            TICKER,
            "124wd5urvxo4H3naXR6QACP1MGVpLeikeR",
            1 ether,
            "TxHash"
        );
        fundsHandler.setPauseState(TICKER, false);
        fundsHandler.setPauseState(bytes32(uint256(CHAIN_ID)), false);
    }

    function accountData() public {
        for (uint8 i; i < 5; ++i) {
            accountManager.registerNewAddress(
                deployer,
                10001 + i,
                IAccountHandler.AddressCategory.EVM,
                i,
                Strings.toHexString(makeAddr(Strings.toString(i)))
            );
        }

        accountManager.registerNewAddress(
            deployer,
            10001,
            IAccountHandler.AddressCategory.BTC,
            0,
            "124wd5urvxo4H3naXR6QACP1MGVpLeikeR"
        );
        accountManager.registerNewAddress(
            deployer,
            10002,
            IAccountHandler.AddressCategory.BTC,
            1,
            "1HkJEUpgptueutWRFB1bjHGKA5wtKBoToW"
        );
        accountManager.registerNewAddress(
            deployer,
            10003,
            IAccountHandler.AddressCategory.BTC,
            2,
            "1PS21zbYxJZUzsHg91MfxUDbqkn7BEw2C5"
        );

        accountManager.registerNewAddress(
            deployer,
            10001,
            IAccountHandler.AddressCategory.SOL,
            0,
            "w9A6215VdjCgX9BVwK1ZXE7sKBuNGh7bdmeGBEs7625"
        );
        accountManager.registerNewAddress(
            deployer,
            10002,
            IAccountHandler.AddressCategory.SOL,
            1,
            "4WMARsRWo8x7oJRwTQ9LhbDuiAnzz5TF3WzpTCgACrfe"
        );
        accountManager.registerNewAddress(
            deployer,
            10003,
            IAccountHandler.AddressCategory.SOL,
            2,
            "8ymc6niJiF4imco29UU3z7mK11sCt9NdL3LjG3VkEYAC"
        );
    }

    function updateTask() public {
        taskManager.updateTask(0, State.Completed, bytes("0x01"));
        taskManager.updateTask(1, State.Pending, bytes("0x02"));
        taskManager.updateTask(2, State.Failed, bytes("0x03"));
    }
}
