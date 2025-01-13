pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {AssetHandlerUpgradeable} from "../src/handlers/AssetHandlerUpgradeable.sol";
import {IAssetHandler, AssetParam, ConsolidateTaskParam, TokenInfo} from "../src/interfaces/IAssetHandler.sol";
import {ITaskManager, Task} from "../src/interfaces/ITaskManager.sol";

contract AssetsTest is BaseTest {
    bytes32 public constant TICKER = "TOKEN_TICKER_18";
    bytes32 public constant FUNDS_ROLE = keccak256("FUNDS_ROLE");
    uint64 public constant CHAIN_ID = 0;
    uint256 public constant MIN_DEPOSIT_AMOUNT = 50;
    uint256 public constant MIN_WITHDRAW_AMOUNT = 50;

    AssetHandlerUpgradeable public assetHandler;

    address public ahProxy;

    function setUp() public override {
        super.setUp();

        // setup assetHandler
        ahProxy = _deployProxy(
            address(new AssetHandlerUpgradeable(address(taskManager))),
            daoContract
        );
        assetHandler = AssetHandlerUpgradeable(ahProxy);
        assetHandler.initialize(daoContract, vmProxy, msgSender);

        // assign handlers
        vm.prank(daoContract);
        assetHandler.grantRole(FUNDS_ROLE, msgSender);
        handlers.push(ahProxy);
        taskManager.initialize(daoContract, vmProxy, handlers);

        // list new asset and token
        vm.startPrank(vmProxy);
        AssetParam memory assetParam = AssetParam(
            18,
            true,
            true,
            MIN_DEPOSIT_AMOUNT,
            MIN_WITHDRAW_AMOUNT,
            ""
        );
        assetHandler.listNewAsset(TICKER, assetParam);
        TokenInfo[] memory testTokenInfo = new TokenInfo[](1);
        testTokenInfo[0] = TokenInfo(CHAIN_ID, true, uint8(18), "0xContractAddress", "SYMBOL", 0);
        assetHandler.linkToken(TICKER, testTokenInfo);
        vm.stopPrank();
    }

    function test_AssetOperations() public {
        vm.startPrank(msgSender);
        // list asset
        bytes32 assetTicker = "TOKEN_TICKER_10";
        assertEq(assetHandler.getAllAssets().length, 1);
        AssetParam memory assetParam = AssetParam(10, false, false, 0, 0, "Token02");
        taskOpts[0].taskId = assetHandler.submitListAssetTask(assetTicker, assetParam);
        signature = _generateOptSignature(taskOpts, tssKey);
        entryPoint.verifyAndCall(taskOpts, signature);
        assertEq(assetHandler.getAllAssets().length, 2);

        // update listed asset
        assertEq(assetHandler.getAssetDetails(TICKER).decimals, 18);
        assetParam = AssetParam(10, false, true, 0, MIN_WITHDRAW_AMOUNT, "Token01");
        taskOpts[0].taskId = assetHandler.submitAssetTask(
            TICKER,
            abi.encodeWithSelector(assetHandler.updateAsset.selector, TICKER, assetParam)
        );
        signature = _generateOptSignature(taskOpts, tssKey);
        entryPoint.verifyAndCall(taskOpts, signature);
        assertEq(assetHandler.getAssetDetails(TICKER).decimals, 10);

        // link new token
        TokenInfo[] memory newTokens = new TokenInfo[](2);
        newTokens[0] = TokenInfo(
            uint64(0x01),
            true,
            uint8(18),
            "0xNewTokenContractAddress",
            "TOKEN_SYMBOL",
            1 ether
        );
        newTokens[1] = TokenInfo(
            uint64(0x02),
            true,
            uint8(18),
            "0xNewTokenContractAddress2",
            "TOKEN_SYMBOL2",
            5 ether
        );
        taskOpts[0].taskId = assetHandler.submitAssetTask(
            TICKER,
            abi.encodeWithSelector(assetHandler.linkToken.selector, TICKER, newTokens)
        );
        signature = _generateOptSignature(taskOpts, tssKey);
        entryPoint.verifyAndCall(taskOpts, signature);
        assertEq(assetHandler.getAllLinkedTokens(TICKER).length, 3);
        assertEq(assetHandler.linkedTokenList(TICKER, 2), uint64(0x02));

        // deactive token
        assertTrue(assetHandler.getLinkedToken(TICKER, CHAIN_ID).isActive);
        taskOpts[0].taskId = assetHandler.submitAssetTask(
            TICKER,
            abi.encodeWithSelector(assetHandler.tokenSwitch.selector, TICKER, CHAIN_ID, false)
        );
        signature = _generateOptSignature(taskOpts, tssKey);
        entryPoint.verifyAndCall(taskOpts, signature);
        assertFalse(assetHandler.getLinkedToken(TICKER, CHAIN_ID).isActive);

        // unlink tokens
        taskOpts[0].taskId = assetHandler.submitAssetTask(
            TICKER,
            abi.encodeWithSelector(assetHandler.resetlinkedToken.selector, TICKER)
        );
        signature = _generateOptSignature(taskOpts, tssKey);
        entryPoint.verifyAndCall(taskOpts, signature);
        assertEq(assetHandler.getAllLinkedTokens(TICKER).length, 0);
        assertFalse(assetHandler.getLinkedToken(TICKER, CHAIN_ID).isActive);

        // delist asset
        assertTrue(assetHandler.isAssetListed(TICKER));
        taskOpts[0].taskId = assetHandler.submitAssetTask(
            TICKER,
            abi.encodeWithSelector(assetHandler.delistAsset.selector, TICKER)
        );
        signature = _generateOptSignature(taskOpts, tssKey);
        entryPoint.verifyAndCall(taskOpts, signature);
        vm.expectRevert(abi.encodeWithSelector(IAssetHandler.AssetNotListed.selector, TICKER));
        assetHandler.getAssetDetails(TICKER);
        assertFalse(assetHandler.isAssetListed(TICKER));

        vm.stopPrank();
    }

    function test_ListAsset() public {
        vm.startPrank(msgSender);
        ConsolidateTaskParam[] memory consolidateParams = new ConsolidateTaskParam[](1);
        consolidateParams[0] = ConsolidateTaskParam(
            "0xFromAddress",
            TICKER,
            CHAIN_ID,
            1 ether,
            "txHash"
        );
        assetHandler.submitConsolidateTask(consolidateParams);
        signature = _generateOptSignature(taskOpts, tssKey);
        entryPoint.verifyAndCall(taskOpts, signature);
        vm.stopPrank();
    }
}
