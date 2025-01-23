pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {TestHelper} from "./utils/TestHelper.sol";

import {AssetHandlerUpgradeable, AssetParam, TokenInfo} from "../src/handlers/AssetHandlerUpgradeable.sol";
import {FundsHandlerUpgradeable} from "../src/handlers/FundsHandlerUpgradeable.sol";
import {IFundsHandler, DepositInfo, WithdrawalInfo} from "../src/interfaces/IFundsHandler.sol";
import {ITaskManager, State} from "../src/interfaces/ITaskManager.sol";

contract FundsTest is BaseTest {
    bytes32 public constant FUNDS_ROLE = keccak256("FUNDS_ROLE");

    uint64 public constant CHAIN_ID = 1;
    string public constant DEPOSIT_ADDRESS = "0xDepositAddress";
    bytes32 public constant TICKER = "TOKEN_TICKER_18";
    uint256 public constant MIN_DEFAULT_AMOUNT = 50;
    uint256 public constant MIN_WITHDRAW_AMOUNT = 50;
    uint256 public constant DEFAULT_AMOUNT = 1 ether;

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
        address fundsHandlerProxy = _deployProxy(
            address(new FundsHandlerUpgradeable(ahProxy, address(taskManager))),
            daoContract
        );
        fundsHandler = FundsHandlerUpgradeable(fundsHandlerProxy);
        fundsHandler.initialize(daoContract, entryPointProxy, msgSender);
        assertTrue(fundsHandler.hasRole(ENTRYPOINT_ROLE, entryPointProxy));

        // assign handlers
        assetHandler.grantRole(FUNDS_ROLE, fundsHandlerProxy);
        handlers.push(fundsHandlerProxy);
        taskManager.initialize(daoContract, entryPointProxy, handlers);

        // default task param
        depositTaskParams.push(
            DepositInfo(
                msgSender,
                CHAIN_ID,
                TICKER,
                DEPOSIT_ADDRESS,
                DEFAULT_AMOUNT,
                "txHash",
                100,
                0
            )
        );
        withdrawTaskParams.push(
            WithdrawalInfo(msgSender, CHAIN_ID, TICKER, DEPOSIT_ADDRESS, DEFAULT_AMOUNT)
        );
    }

    function test_Pause() public {
        vm.startPrank(msgSender);
        assertFalse(fundsHandler.pauseState(TICKER));
        // pause
        bytes32[] memory conditions = new bytes32[](1);
        conditions[0] = TICKER;
        bool[] memory newStates = new bool[](1);
        newStates[0] = true;
        fundsHandler.submitSetPauseState(conditions, newStates);

        signature = _generateOptSignature(taskOpts, tssKey);
        entryPoint.verifyAndCall(taskOpts, signature);
        assertTrue(fundsHandler.pauseState(TICKER));
        vm.stopPrank();
    }

    function test_Deposit() public {
        vm.startPrank(msgSender);
        // setup deposit info
        uint256 depositIndex = fundsHandler.getDeposits(msgSender).length;
        fundsHandler.submitDepositTask(depositTaskParams);
        signature = _generateOptSignature(taskOpts, tssKey);
        // check event and result
        vm.expectEmit(true, true, true, true);
        emit IFundsHandler.DepositRecorded(
            msgSender,
            TICKER,
            CHAIN_ID,
            DEPOSIT_ADDRESS,
            DEFAULT_AMOUNT,
            "txHash",
            100,
            0
        );
        entryPoint.verifyAndCall(taskOpts, signature);

        DepositInfo memory depositInfo = fundsHandler.getDeposit(msgSender, depositIndex);
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
        depositIndex = fundsHandler.getDeposits(msgSender).length;
        assertEq(depositIndex, 1); // should have increased by 1
        uint64 newChainId = uint64(1);
        uint256 newAmount = 5 ether;
        depositTaskParams[0].chainId = newChainId;
        depositTaskParams[0].amount = newAmount;
        fundsHandler.submitDepositTask(depositTaskParams);
        taskOpts[0].taskId++;
        signature = _generateOptSignature(taskOpts, tssKey);

        // check event and result
        vm.expectEmit(true, true, true, true);
        emit IFundsHandler.DepositRecorded(
            msgSender,
            TICKER,
            newChainId,
            DEPOSIT_ADDRESS,
            newAmount,
            "txHash",
            100,
            0
        );
        entryPoint.verifyAndCall(taskOpts, signature);
        depositInfo = fundsHandler.getDeposit(msgSender, depositIndex);
        assertEq(
            abi.encodePacked(DEPOSIT_ADDRESS, TICKER, newChainId, newAmount),
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

        vm.prank(entryPointProxy);
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
                CHAIN_ID,
                TICKER,
                depositAddresses[i],
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
            depositInfo = fundsHandler.getDeposit(msgSender, i);
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
        uint256 depositIndex = fundsHandler.getDeposits(msgSender).length;
        depositTaskParams[0].depositAddress = _depositAddress;
        depositTaskParams[0].amount = _amount;
        fundsHandler.submitDepositTask(depositTaskParams);
        signature = _generateOptSignature(taskOpts, tssKey);

        // check event and result
        vm.expectEmit(true, true, true, true);
        emit IFundsHandler.DepositRecorded(
            msgSender,
            TICKER,
            CHAIN_ID,
            _depositAddress,
            _amount,
            "txHash",
            100,
            0
        );
        entryPoint.verifyAndCall(taskOpts, signature);
        DepositInfo memory depositInfo = fundsHandler.getDeposit(msgSender, depositIndex);
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
        vm.startPrank(msgSender);
        // setup withdrawal info
        uint256 withdrawIndex = fundsHandler.getWithdrawals(msgSender).length;
        string
            memory withdrawTxHash = "--------------------------------txHash--------------------------------";
        assertEq(withdrawIndex, 0);
        fundsHandler.submitWithdrawTask(withdrawTaskParams);

        // pending task
        taskOpts[0].state = State.Pending;
        taskOpts[0].extraData = TestHelper.getPaddedString(withdrawTxHash);
        signature = _generateOptSignature(taskOpts, tssKey);
        entryPoint.verifyAndCall(taskOpts, signature);

        // completed task
        taskOpts[0].state = State.Completed;
        taskOpts[0].extraData = "";
        signature = _generateOptSignature(taskOpts, tssKey);
        // check event and result
        vm.expectEmit(true, true, true, true);
        emit IFundsHandler.WithdrawalRecorded(
            msgSender,
            TICKER,
            CHAIN_ID,
            DEPOSIT_ADDRESS,
            DEFAULT_AMOUNT,
            withdrawTxHash
        );
        entryPoint.verifyAndCall(taskOpts, signature);
        WithdrawalInfo memory withdrawInfo = fundsHandler.getWithdrawal(msgSender, withdrawIndex);
        assertEq(
            abi.encodePacked(msgSender, CHAIN_ID, DEFAULT_AMOUNT),
            abi.encodePacked(withdrawInfo.userAddress, withdrawInfo.chainId, withdrawInfo.amount)
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
        withdrawTaskParams[0].toAddress = "";
        vm.expectRevert(IFundsHandler.InvalidAddress.selector);
        fundsHandler.submitWithdrawTask(withdrawTaskParams);
        vm.stopPrank();

        // fail case: paused
        vm.prank(entryPointProxy);
        fundsHandler.setPauseState(TICKER, true);
        withdrawTaskParams[0].userAddress = msgSender;
        vm.expectRevert(IFundsHandler.Paused.selector);
        vm.prank(msgSender);
        fundsHandler.submitWithdrawTask(withdrawTaskParams);
    }

    function test_WithdrawBatch() public {
        vm.startPrank(msgSender);
        uint8 batchSize = 20;
        // setup withdraw info
        TaskOperation[] memory taskOperations = new TaskOperation[](batchSize);
        uint256[] memory amounts = new uint256[](batchSize);
        WithdrawalInfo[] memory batchWithdrawTaskParams = new WithdrawalInfo[](batchSize);
        for (uint8 i; i < batchSize; ++i) {
            amounts[i] = 1 ether * (uint256(i) + 1);
            batchWithdrawTaskParams[i] = WithdrawalInfo(
                msgSender,
                CHAIN_ID,
                TICKER,
                DEPOSIT_ADDRESS,
                amounts[i]
            );
            taskOperations[i] = TaskOperation(
                i,
                State.Pending,
                TestHelper.getPaddedString("txHash")
            );
        }
        fundsHandler.submitWithdrawTask(batchWithdrawTaskParams);
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
            taskOperations[i].extraData = "";
        }
        signature = _generateOptSignature(taskOperations, tssKey);
        entryPoint.verifyAndCall(taskOperations, signature);
        WithdrawalInfo memory withdrawalInfo;
        for (uint16 i; i < batchSize; ++i) {
            assertEq(
                uint8(taskManager.getTaskState(taskOperations[i].taskId)),
                uint8(State.Completed)
            );
            withdrawalInfo = fundsHandler.getWithdrawal(msgSender, i);
            assertEq(amounts[i], withdrawalInfo.amount);
        }
        vm.stopPrank();
    }

    function testFuzz_WithdrawFuzz(
        string calldata _toAddress,
        uint256 _amount,
        string calldata _txHash
    ) public {
        vm.startPrank(msgSender);
        vm.assume(bytes(_toAddress).length > 0);
        vm.assume(_amount > MIN_DEFAULT_AMOUNT);
        vm.assume(bytes(_txHash).length > 0);
        // setup withdrawal info
        WithdrawalInfo[] memory tempWithdrawTaskParams = new WithdrawalInfo[](1);
        tempWithdrawTaskParams[0] = WithdrawalInfo(
            msgSender,
            CHAIN_ID,
            TICKER,
            _toAddress,
            _amount
        );
        fundsHandler.submitWithdrawTask(tempWithdrawTaskParams);

        // pending task
        taskOpts[0].state = State.Pending;
        taskOpts[0].extraData = TestHelper.getPaddedString(_txHash);
        signature = _generateOptSignature(taskOpts, tssKey);
        entryPoint.verifyAndCall(taskOpts, signature);

        // completed task
        taskOpts[0].state = State.Completed;
        taskOpts[0].extraData = "";
        signature = _generateOptSignature(taskOpts, tssKey);
        // check event and result
        vm.expectEmit(true, true, true, true);
        emit IFundsHandler.WithdrawalRecorded(
            msgSender,
            TICKER,
            CHAIN_ID,
            _toAddress,
            _amount,
            _txHash
        );
        entryPoint.verifyAndCall(taskOpts, signature);
        vm.stopPrank();
    }
}
