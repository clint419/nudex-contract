pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {TestHelper} from "./utils/TestHelper.sol";

import {AssetHandlerUpgradeable} from "../src/handlers/AssetHandlerUpgradeable.sol";
import {IAssetHandler, AssetParam, Pair, PairState, PairType, TokenInfo} from "../src/interfaces/IAssetHandler.sol";
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
        assetHandler.resetLinkedToken(TICKER);
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

    function test_Pause() public {
        assertFalse(assetHandler.pauseState(TICKER));
        vm.prank(daoContract);
        assetHandler.setPauseState(TICKER, true);
        assertTrue(assetHandler.pauseState(TICKER));
    }
}
