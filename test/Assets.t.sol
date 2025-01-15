pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {AssetHandlerUpgradeable} from "../src/handlers/AssetHandlerUpgradeable.sol";
import {IAssetHandler, AssetParam, ConsolidateTaskParam, TransferParam, TokenInfo} from "../src/interfaces/IAssetHandler.sol";
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

    function test_Consolidate() public {
        vm.startPrank(msgSender);
        string memory fromAddr = "0xFromAddress";
        uint256 amount = 1 ether;
        string memory txHash = "consolidate_txHash";
        ConsolidateTaskParam[] memory consolidateParams = new ConsolidateTaskParam[](1);

        // empty from address
        consolidateParams[0] = ConsolidateTaskParam("", TICKER, CHAIN_ID, amount);
        vm.expectRevert(IAssetHandler.InvalidAddress.selector);
        assetHandler.submitConsolidateTask(consolidateParams);

        // below minimum amount
        consolidateParams[0] = ConsolidateTaskParam(fromAddr, TICKER, CHAIN_ID, 0);
        vm.expectRevert(IAssetHandler.InvalidAmount.selector);
        assetHandler.submitConsolidateTask(consolidateParams);

        // correct amount
        consolidateParams[0] = ConsolidateTaskParam(fromAddr, TICKER, CHAIN_ID, amount);
        assetHandler.submitConsolidateTask(consolidateParams);
        taskOpts[0].extraData = abi.encode(bytes(txHash).length, bytes32(bytes(txHash)));
        signature = _generateOptSignature(taskOpts, tssKey);

        vm.expectEmit(true, true, true, true);
        emit IAssetHandler.Consolidate(TICKER, CHAIN_ID, fromAddr, amount, txHash);
        entryPoint.verifyAndCall(taskOpts, signature);
        (
            string memory tempAddr,
            bytes32 tempTicker,
            uint64 tempChainId,
            uint256 tempAmount
        ) = assetHandler.consolidateRecords(TICKER, CHAIN_ID, 0);
        assertEq(
            abi.encode(tempAddr, tempTicker, tempChainId, tempAmount),
            abi.encode(fromAddr, TICKER, CHAIN_ID, amount)
        );
        vm.stopPrank();
    }

    function test_Transfer() public {
        vm.startPrank(msgSender);
        string memory fromAddr = "0xFromAddress";
        string memory toAddr = "0xToAddress";
        uint256 amount = 1 ether;
        string memory txHash = "transfer_txHash";
        TransferParam[] memory transferParams = new TransferParam[](1);

        // empty from address
        transferParams[0] = TransferParam("", toAddr, TICKER, CHAIN_ID, amount);
        vm.expectRevert(IAssetHandler.InvalidAddress.selector);
        assetHandler.submitTransferTask(transferParams);

        // empty from address
        transferParams[0] = TransferParam(fromAddr, "", TICKER, CHAIN_ID, amount);
        vm.expectRevert(IAssetHandler.InvalidAddress.selector);
        assetHandler.submitTransferTask(transferParams);

        // below minimum amount
        transferParams[0] = TransferParam(fromAddr, toAddr, TICKER, CHAIN_ID, 0);
        vm.expectRevert(IAssetHandler.InvalidAmount.selector);
        assetHandler.submitTransferTask(transferParams);

        // correct amount
        transferParams[0] = TransferParam(fromAddr, toAddr, TICKER, CHAIN_ID, amount);
        assetHandler.submitTransferTask(transferParams);
        taskOpts[0].extraData = abi.encode(bytes(txHash).length, bytes32(bytes(txHash)));
        signature = _generateOptSignature(taskOpts, tssKey);

        vm.expectEmit(true, true, true, true);
        emit IAssetHandler.Transfer(TICKER, CHAIN_ID, fromAddr, toAddr, amount, txHash);
        entryPoint.verifyAndCall(taskOpts, signature);
        vm.stopPrank();
    }
}
