pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {TestHelper} from "./utils/TestHelper.sol";

import {AssetHandlerUpgradeable} from "../src/handlers/AssetHandlerUpgradeable.sol";
import {IAssetHandler, AssetParam, Pair, PairState, PairType, ConsolidateTaskParam, TransferParam, TokenInfo} from "../src/interfaces/IAssetHandler.sol";
import {ITaskManager, Task} from "../src/interfaces/ITaskManager.sol";

contract AssetsTest is BaseTest {
    bytes32 public constant TICKER = "TOKEN_TICKER_18";
    bytes32 public constant FUNDS_ROLE = keccak256("FUNDS_ROLE");
    uint64 public constant CHAIN_ID = 1;
    uint256 public constant MIN_DEPOSIT_AMOUNT = 50;
    uint256 public constant MIN_WITHDRAW_AMOUNT = 50;

    AssetHandlerUpgradeable public assetHandler;

    function setUp() public override {
        super.setUp();

        // setup assetHandler
        address assetHandlerProxy = _deployProxy(
            address(new AssetHandlerUpgradeable(address(taskManager))),
            daoContract
        );
        assetHandler = AssetHandlerUpgradeable(assetHandlerProxy);
        assetHandler.initialize(daoContract, entryPointProxy, msgSender);

        // assign handlers
        vm.startPrank(daoContract);
        assetHandler.grantRole(FUNDS_ROLE, msgSender);
        handlers.push(assetHandlerProxy);
        taskManager.initialize(daoContract, entryPointProxy, handlers);

        // list new asset and token
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
        vm.startPrank(daoContract);
        // list asset
        bytes32 assetBTicker = "TOKEN_TICKER_10";
        assertEq(assetHandler.getAllAssets().length, 1);
        AssetParam memory assetParam = AssetParam(10, false, false, 0, 0, "Token02");
        assetHandler.listNewAsset(assetBTicker, assetParam);
        assertEq(assetHandler.getAllAssets().length, 2);

        // update listed asset
        assertEq(assetHandler.getAssetDetails(TICKER).decimals, 18);
        assetParam = AssetParam(10, false, true, 0, MIN_WITHDRAW_AMOUNT, "Token01");
        assetHandler.updateAsset(TICKER, assetParam);
        assertEq(assetHandler.getAssetDetails(TICKER).decimals, 10);

        // add pair
        Pair[] memory pairs = new Pair[](1);
        pairs[0] = Pair(
            TICKER,
            assetBTicker,
            PairState.Active,
            PairType.Spot,
            18,
            18,
            0,
            0,
            3 ether,
            1 ether,
            30 ether,
            10 ether
        );
        assetHandler.addPair(pairs);
        // check index, should match 1 both ways
        assertEq(assetHandler.getPairIndex(TICKER, assetBTicker), 1);
        assertEq(assetHandler.getPairIndex(assetBTicker, TICKER), 1);
        assertEq(assetHandler.getPairInfo(assetBTicker, TICKER).listedTime, block.timestamp);
        assertEq(assetHandler.getPairInfo(assetBTicker, TICKER).activeTime, block.timestamp);

        // link new token
        TokenInfo[] memory newTokens = new TokenInfo[](2);
        newTokens[0] = TokenInfo(
            uint64(0x02),
            true,
            uint8(18),
            "0xNewTokenContractAddress",
            "TOKEN_SYMBOL",
            1 ether
        );
        newTokens[1] = TokenInfo(
            uint64(0x03),
            true,
            uint8(18),
            "0xNewTokenContractAddress2",
            "TOKEN_SYMBOL2",
            5 ether
        );
        assetHandler.linkToken(TICKER, newTokens);
        assertEq(assetHandler.getAllLinkedTokens(TICKER).length, 3);
        assertEq(assetHandler.linkedTokenList(TICKER, 2), uint64(0x03));

        // update linked token
        TokenInfo memory tokenInfo = TokenInfo(
            uint64(0x01),
            true,
            uint8(18),
            "0xNewTokenContractAddress",
            "TOKEN_SYMBOL",
            2 ether
        );
        assetHandler.updateToken(TICKER, tokenInfo);
        assertEq(assetHandler.getLinkedToken(TICKER, CHAIN_ID).withdrawFee, 2 ether);
        // fail case: update non-existing token
        tokenInfo.chainId = uint64(0x99);
        vm.expectRevert("Token not linked");
        assetHandler.updateToken(TICKER, tokenInfo);

        // deactive token
        assertTrue(assetHandler.getLinkedToken(TICKER, CHAIN_ID).isActive);
        assetHandler.tokenSwitch(TICKER, CHAIN_ID, false);
        assertFalse(assetHandler.getLinkedToken(TICKER, CHAIN_ID).isActive);

        // unlink tokens
        assetHandler.resetlinkedToken(TICKER);
        signature = _generateOptSignature(taskOpts, tssKey);
        assertFalse(assetHandler.getLinkedToken(TICKER, CHAIN_ID).isActive);

        // delist asset
        assertTrue(assetHandler.isAssetListed(TICKER));
        assetHandler.delistAsset(TICKER);
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
        vm.expectRevert("Invalid address");
        assetHandler.submitConsolidateTask(consolidateParams);

        // below minimum amount
        consolidateParams[0] = ConsolidateTaskParam(fromAddr, TICKER, CHAIN_ID, 0);
        vm.expectRevert("Invalid amount");
        assetHandler.submitConsolidateTask(consolidateParams);

        // correct amount
        consolidateParams[0] = ConsolidateTaskParam(fromAddr, TICKER, CHAIN_ID, amount);
        assetHandler.submitConsolidateTask(consolidateParams);
        taskOpts[0].extraData = TestHelper.getPaddedString(txHash);
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
        vm.expectRevert("Invalid address");
        assetHandler.submitTransferTask(transferParams);

        // empty from address
        transferParams[0] = TransferParam(fromAddr, "", TICKER, CHAIN_ID, amount);
        vm.expectRevert("Invalid address");
        assetHandler.submitTransferTask(transferParams);

        // below minimum amount
        transferParams[0] = TransferParam(fromAddr, toAddr, TICKER, CHAIN_ID, 0);
        vm.expectRevert("Invalid amount");
        assetHandler.submitTransferTask(transferParams);

        // correct amount
        transferParams[0] = TransferParam(fromAddr, toAddr, TICKER, CHAIN_ID, amount);
        assetHandler.submitTransferTask(transferParams);
        taskOpts[0].extraData = TestHelper.getPaddedString(txHash);
        signature = _generateOptSignature(taskOpts, tssKey);

        vm.expectEmit(true, true, true, true);
        emit IAssetHandler.Transfer(TICKER, CHAIN_ID, fromAddr, toAddr, amount, txHash);
        entryPoint.verifyAndCall(taskOpts, signature);
        vm.stopPrank();
    }
}
