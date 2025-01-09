pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {AssetHandlerUpgradeable, AssetParam, TokenInfo} from "../src/handlers/AssetHandlerUpgradeable.sol";
import {FundsHandlerUpgradeable} from "../src/handlers/FundsHandlerUpgradeable.sol";
import {IFundsHandler, DepositInfo, WithdrawalInfo} from "../src/interfaces/IFundsHandler.sol";
import {ITaskManager, State} from "../src/interfaces/ITaskManager.sol";

contract FundsTest is BaseTest {
    bytes32 public constant FUNDS_ROLE = keccak256("FUNDS_ROLE");

    string public constant DEPOSIT_ADDRESS = "0xDepositAddress";
    bytes32 public constant TICKER = "TOKEN_TICKER_18";
    bytes32 public constant CHAIN_ID = 0;
    uint256 public constant MIN_DEFAULT_AMOUNT = 50;
    uint256 public constant MIN_WITHDRAW_AMOUNT = 50;
    uint256 public constant DEFAULT_AMOUNT = 1 ether;

    address public dmProxy;
    FundsHandlerUpgradeable public fundsHandler;

    DepositInfo[] public depositTaskParams;
    WithdrawalInfo[] public withdrawTaskParams;

    function setUp() public override {
        super.setUp();

        // setup assetHandler
        address ahProxy = _deployProxy(
            address(new AssetHandlerUpgradeable(address(taskManager))),
            daoContract
        );
        AssetHandlerUpgradeable assetHandler = AssetHandlerUpgradeable(ahProxy);
        assetHandler.initialize(thisAddr, thisAddr, msgSender);
        AssetParam memory assetParam = AssetParam(
            18,
            true,
            true,
            MIN_DEFAULT_AMOUNT,
            MIN_WITHDRAW_AMOUNT,
            ""
        );
        assetHandler.listNewAsset(TICKER, assetParam);
        TokenInfo[] memory testTokenInfo = new TokenInfo[](1);
        testTokenInfo[0] = TokenInfo(CHAIN_ID, true, uint8(18), "0xContractAddress", "SYMBOL", 0);
        assetHandler.linkToken(TICKER, testTokenInfo);
        // deploy fundsHandler
        dmProxy = _deployProxy(
            address(new FundsHandlerUpgradeable(ahProxy, address(taskManager))),
            daoContract
        );
        fundsHandler = FundsHandlerUpgradeable(dmProxy);
        fundsHandler.initialize(daoContract, vmProxy, msgSender);
        assertTrue(fundsHandler.hasRole(ENTRYPOINT_ROLE, vmProxy));

        // assign handlers
        assetHandler.grantRole(FUNDS_ROLE, dmProxy);
        handlers.push(dmProxy);
        taskManager.initialize(daoContract, vmProxy, handlers);

        // default task param
        depositTaskParams.push(
            DepositInfo(
                msgSender,
                DEPOSIT_ADDRESS,
                TICKER,
                CHAIN_ID,
                DEFAULT_AMOUNT,
                "txHash",
                100,
                0
            )
        );
        withdrawTaskParams.push(
            WithdrawalInfo(msgSender, DEPOSIT_ADDRESS, TICKER, CHAIN_ID, DEFAULT_AMOUNT)
        );
    }

    function test_Deposit() public {
        vm.startPrank(msgSender);
        // setup deposit info
        uint256 depositIndex = fundsHandler.getDeposits(DEPOSIT_ADDRESS).length;
        fundsHandler.submitDepositTask(depositTaskParams);
        signature = _generateOptSignature(taskOpts, tssKey);
        // check event and result
        vm.expectEmit(true, true, true, true);
        emit IFundsHandler.DepositRecorded(
            msgSender,
            DEPOSIT_ADDRESS,
            TICKER,
            CHAIN_ID,
            DEFAULT_AMOUNT,
            "txHash",
            100,
            0
        );
        entryPoint.verifyAndCall(taskOpts, signature);

        DepositInfo memory depositInfo = fundsHandler.getDeposit(DEPOSIT_ADDRESS, depositIndex);
        assertEq(
            abi.encodePacked(DEPOSIT_ADDRESS, TICKER, CHAIN_ID, DEFAULT_AMOUNT),
            abi.encodePacked(
                depositInfo.depositAddress,
                depositInfo.ticker,
                depositInfo.chainId,
                depositInfo.amount
            )
        );

        // second deposit
        // setup deposit info
        depositIndex = fundsHandler.getDeposits(DEPOSIT_ADDRESS).length;
        assertEq(depositIndex, 1); // should have increased by 1
        depositTaskParams[0].chainId = bytes32(uint256(1));
        depositTaskParams[0].amount = 5 ether;
        fundsHandler.submitDepositTask(depositTaskParams);
        taskOpts[0].taskId++;
        signature = _generateOptSignature(taskOpts, tssKey);

        // check event and result
        vm.expectEmit(true, true, true, true);
        emit IFundsHandler.DepositRecorded(
            msgSender,
            DEPOSIT_ADDRESS,
            TICKER,
            bytes32(uint256(1)),
            5 ether,
            "txHash",
            100,
            0
        );
        entryPoint.verifyAndCall(taskOpts, signature);
        depositInfo = fundsHandler.getDeposit(DEPOSIT_ADDRESS, depositIndex);
        assertEq(
            abi.encodePacked(DEPOSIT_ADDRESS, TICKER, bytes32(uint256(1)), uint256(5 ether)),
            abi.encodePacked(
                depositInfo.depositAddress,
                depositInfo.ticker,
                depositInfo.chainId,
                depositInfo.amount
            )
        );
        vm.stopPrank();
    }

    function test_DepositTaskRevert() public {
        vm.startPrank(msgSender);
        depositTaskParams[0].amount = 0; // invalid amount
        // fail case: invalid amount
        vm.expectRevert(IFundsHandler.InvalidAmount.selector);
        fundsHandler.submitDepositTask(depositTaskParams);

        // fail case: invalid user address
        depositTaskParams[0].amount = 1 ether;
        depositTaskParams[0].depositAddress = "";
        vm.expectRevert(IFundsHandler.InvalidAddress.selector);
        fundsHandler.submitDepositTask(depositTaskParams);
        vm.stopPrank();

        vm.prank(vmProxy);
        fundsHandler.setPauseState(TICKER, true);
        vm.expectRevert(IFundsHandler.Paused.selector);
        vm.prank(msgSender);
        fundsHandler.submitDepositTask(depositTaskParams);
    }

    function test_DepositBatch() public {
        vm.startPrank(msgSender);
        uint8 batchSize = 20;
        // setup deposit info
        TaskOperation[] memory taskOperations = new TaskOperation[](batchSize);
        string[] memory depositAddresses = new string[](batchSize);
        uint256[] memory amounts = new uint256[](batchSize);
        DepositInfo[] memory batchDepositTaskParams = new DepositInfo[](batchSize);
        for (uint8 i; i < batchSize; ++i) {
            depositAddresses[i] = string(abi.encodePacked("depositAddress", i));
            amounts[i] = 1 ether;
            batchDepositTaskParams[i] = DepositInfo(
                msgSender,
                depositAddresses[i],
                TICKER,
                CHAIN_ID,
                amounts[i],
                "txHash",
                100,
                0
            );
            taskOperations[i] = TaskOperation(i, State.Pending, "");
        }
        fundsHandler.submitDepositTask(batchDepositTaskParams);
        for (uint16 i; i < batchSize; ++i) {
            assertEq(
                uint8(taskManager.getTaskState(taskOperations[i].taskId)),
                uint8(State.Created)
            );
        }
        signature = _generateOptSignature(taskOperations, tssKey);
        entryPoint.verifyAndCall(taskOperations, signature);

        for (uint16 i; i < batchSize; ++i) {
            assertEq(
                uint8(taskManager.getTaskState(taskOperations[i].taskId)),
                uint8(State.Pending)
            );
            taskOperations[i].state = State.Completed;
        }
        signature = _generateOptSignature(taskOperations, tssKey);
        entryPoint.verifyAndCall(taskOperations, signature);
        DepositInfo memory depositInfo;
        for (uint8 i; i < batchSize; ++i) {
            assertEq(
                uint8(taskManager.getTaskState(taskOperations[i].taskId)),
                uint8(State.Completed)
            );
            depositInfo = fundsHandler.getDeposit(depositAddresses[i], 0);
            assertEq(
                abi.encodePacked(depositAddresses[i], amounts[i]),
                abi.encodePacked(depositInfo.depositAddress, depositInfo.amount)
            );
        }
        vm.stopPrank();
    }

    function testFuzz_DepositFuzz(string calldata _depositAddress, uint256 _amount) public {
        vm.startPrank(msgSender);
        vm.assume(bytes(_depositAddress).length > 0);
        vm.assume(_amount > MIN_DEFAULT_AMOUNT);
        // setup deposit info
        uint256 depositIndex = fundsHandler.getDeposits(_depositAddress).length;
        depositTaskParams[0].depositAddress = _depositAddress;
        depositTaskParams[0].amount = _amount;
        fundsHandler.submitDepositTask(depositTaskParams);
        signature = _generateOptSignature(taskOpts, tssKey);

        // check event and result
        vm.expectEmit(true, true, true, true);
        emit IFundsHandler.DepositRecorded(
            msgSender,
            _depositAddress,
            TICKER,
            CHAIN_ID,
            _amount,
            "txHash",
            100,
            0
        );
        entryPoint.verifyAndCall(taskOpts, signature);
        DepositInfo memory depositInfo = fundsHandler.getDeposit(_depositAddress, depositIndex);
        assertEq(
            abi.encodePacked(_depositAddress, TICKER, CHAIN_ID, _amount),
            abi.encodePacked(
                depositInfo.depositAddress,
                depositInfo.ticker,
                depositInfo.chainId,
                depositInfo.amount
            )
        );
        vm.stopPrank();
    }

    function test_Withdraw() public {
        vm.prank(msgSender);
        fundsHandler.submitWithdrawTask(withdrawTaskParams);
        vm.prank(vmProxy);
        fundsHandler.recordWithdrawal(withdrawTaskParams[0], "txHash");
        return;
        vm.startPrank(msgSender);
        // setup withdrawal info
        uint256 withdrawIndex = fundsHandler.getWithdrawals(DEPOSIT_ADDRESS).length;
        assertEq(withdrawIndex, 0);
        fundsHandler.submitWithdrawTask(withdrawTaskParams);
        signature = _generateOptSignature(taskOpts, tssKey);
        // check event and result
        vm.expectEmit(true, true, true, true);
        emit IFundsHandler.WithdrawalRecorded(
            msgSender,
            DEPOSIT_ADDRESS,
            TICKER,
            CHAIN_ID,
            DEFAULT_AMOUNT,
            "txHash"
        );
        entryPoint.verifyAndCall(taskOpts, signature);
        WithdrawalInfo memory withdrawInfo = fundsHandler.getWithdrawal(
            DEPOSIT_ADDRESS,
            withdrawIndex
        );
        assertEq(
            abi.encodePacked(DEPOSIT_ADDRESS, CHAIN_ID, DEFAULT_AMOUNT),
            abi.encodePacked(withdrawInfo.depositAddress, withdrawInfo.chainId, withdrawInfo.amount)
        );
        vm.stopPrank();
    }

    function test_WithdrawRevert() public {
        vm.startPrank(msgSender);
        // setup withdraw info
        withdrawTaskParams[0].amount = 0; // invalid amount
        // fail case: invalid amount
        vm.expectRevert(IFundsHandler.InvalidAmount.selector);
        fundsHandler.submitWithdrawTask(withdrawTaskParams);
        // fail case: invalid deposit address
        withdrawTaskParams[0].amount = 1 ether;
        withdrawTaskParams[0].depositAddress = "";
        vm.expectRevert(IFundsHandler.InvalidAddress.selector);
        fundsHandler.submitWithdrawTask(withdrawTaskParams);
        vm.stopPrank();

        vm.prank(vmProxy);
        fundsHandler.setPauseState(TICKER, true);
        withdrawTaskParams[0].depositAddress = DEPOSIT_ADDRESS;
        vm.expectRevert(IFundsHandler.Paused.selector);
        vm.prank(msgSender);
        fundsHandler.submitWithdrawTask(withdrawTaskParams);
    }

    function test_WithdrawBatch() public {
        vm.skip(true);
        vm.startPrank(msgSender);
        uint8 batchSize = 20;
        // setup withdraw info
        TaskOperation[] memory taskOperations = new TaskOperation[](batchSize);
        string[] memory depositAddresses = new string[](batchSize);
        uint256[] memory amounts = new uint256[](batchSize);
        WithdrawalInfo[] memory batchWithdrawTaskParams = new WithdrawalInfo[](batchSize);
        for (uint8 i; i < batchSize; ++i) {
            depositAddresses[i] = string(abi.encodePacked("depositAddress", i));
            amounts[i] = 1 ether * (uint256(i) + 1);
            batchWithdrawTaskParams[i] = WithdrawalInfo(
                msgSender,
                depositAddresses[i],
                TICKER,
                CHAIN_ID,
                amounts[i]
            );
            taskOperations[i] = TaskOperation(i, State.Pending, "");
        }
        fundsHandler.submitWithdrawTask(batchWithdrawTaskParams);
        for (uint16 i; i < batchSize; ++i) {
            assertEq(
                uint8(taskManager.getTaskState(taskOperations[i].taskId)),
                uint8(State.Created)
            );
        }
        console.log("point 3");
        signature = _generateOptSignature(taskOperations, tssKey);
        entryPoint.verifyAndCall(taskOperations, signature);
        for (uint16 i; i < batchSize; ++i) {
            assertEq(
                uint8(taskManager.getTaskState(taskOperations[i].taskId)),
                uint8(State.Pending)
            );
            taskOperations[i].state = State.Completed;
        }
        console.log("point 4");
        signature = _generateOptSignature(taskOperations, tssKey);
        entryPoint.verifyAndCall(taskOperations, signature);
        WithdrawalInfo memory withdrawalInfo;
        for (uint16 i; i < batchSize; ++i) {
            assertEq(
                uint8(taskManager.getTaskState(taskOperations[i].taskId)),
                uint8(State.Completed)
            );
            withdrawalInfo = fundsHandler.getWithdrawal(depositAddresses[i], 0);
            assertEq(
                abi.encodePacked(depositAddresses[i], amounts[i]),
                abi.encodePacked(withdrawalInfo.depositAddress, withdrawalInfo.amount)
            );
        }
        vm.stopPrank();
    }
}
