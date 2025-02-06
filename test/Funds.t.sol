pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {TestHelper} from "./utils/TestHelper.sol";

import {AssetHandlerUpgradeable, AssetParam, TokenInfo} from "../src/handlers/AssetHandlerUpgradeable.sol";
import {FundsHandlerUpgradeable} from "../src/handlers/FundsHandlerUpgradeable.sol";
import {IFundsHandler, DepositInfo, WithdrawalInfo, ConsolidateTaskParam, TransferParam} from "../src/interfaces/IFundsHandler.sol";
import {ITaskManager, State} from "../src/interfaces/ITaskManager.sol";

contract FundsTest is BaseTest {
    bytes32 public constant FUNDS_ROLE = keccak256("FUNDS_ROLE");

    uint64 public constant CHAIN_ID = 1;
    string public constant DEPOSIT_ADDRESS = "0xDepositAddress";
    bytes32 public constant TICKER = "TOKEN_TICKER_18";
    uint256 public constant MIN_DEFAULT_AMOUNT = 50;
    uint256 public constant MIN_WITHDRAW_AMOUNT = 50;
    uint256 public constant DEFAULT_AMOUNT = 1 ether;
    uint256 public constant WITHDRAW_FEE = 0.1 ether;

    AssetHandlerUpgradeable assetHandler;
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
        assetHandler = AssetHandlerUpgradeable(ahProxy);
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
        testTokenInfo[0] = TokenInfo(
            CHAIN_ID,
            true,
            uint8(18),
            "0xContractAddress",
            "SYMBOL",
            WITHDRAW_FEE
        );
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
            WithdrawalInfo(
                msgSender,
                CHAIN_ID,
                TICKER,
                DEPOSIT_ADDRESS,
                DEFAULT_AMOUNT,
                bytes32(uint256(0))
            )
        );
    }

    function test_Deposit() public {
        vm.startPrank(msgSender);
        // setup deposit info
        uint256 depositIndex = fundsHandler.getDeposits(msgSender).length;
        fundsHandler.submitDepositTask(depositTaskParams);
        taskOpts[0].initialCalldata = abi.encodeWithSelector(
            fundsHandler.recordDeposit.selector,
            depositTaskParams[0]
        );
        signature = _generateOptSignature(taskOpts, tssKey);
        // check event and result
        vm.expectEmit(true, true, true, true);
        emit ITaskManager.TaskUpdated(
            taskOpts[0].taskId,
            address(fundsHandler),
            State.Completed,
            block.timestamp
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
        taskOpts[0].initialCalldata = abi.encodeWithSelector(
            fundsHandler.recordDeposit.selector,
            depositTaskParams[0]
        );
        signature = _generateOptSignature(taskOpts, tssKey);

        // check event and result
        vm.expectEmit(true, true, true, true);
        emit ITaskManager.TaskUpdated(
            taskOpts[0].taskId,
            address(fundsHandler),
            State.Completed,
            block.timestamp
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
            taskOperations[i] = TaskOperation(
                i + 1,
                State.Pending,
                abi.encodeWithSelector(
                    fundsHandler.recordDeposit.selector,
                    batchDepositTaskParams[i]
                ),
                ""
            );
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

        taskOpts[0].initialCalldata = abi.encodeWithSelector(
            fundsHandler.recordDeposit.selector,
            depositTaskParams[0]
        );
        signature = _generateOptSignature(taskOpts, tssKey);

        // check event and result
        vm.expectEmit(true, true, true, true);
        emit ITaskManager.TaskUpdated(
            taskOpts[0].taskId,
            address(fundsHandler),
            State.Completed,
            block.timestamp
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
        taskOpts[0].initialCalldata = abi.encodeWithSelector(
            fundsHandler.recordWithdrawal.selector,
            withdrawTaskParams[0].userAddress,
            withdrawTaskParams[0].chainId,
            withdrawTaskParams[0].ticker,
            withdrawTaskParams[0].toAddress,
            withdrawTaskParams[0].amount - WITHDRAW_FEE,
            WITHDRAW_FEE,
            withdrawTaskParams[0].salt,
            uint256(320)
        );
        signature = _generateOptSignature(taskOpts, tssKey);
        entryPoint.verifyAndCall(taskOpts, signature);

        // completed task
        taskOpts[0].state = State.Completed;
        taskOpts[0].extraData = TestHelper.getPaddedString(withdrawTxHash);
        signature = _generateOptSignature(taskOpts, tssKey);
        // check event and result
        vm.expectEmit(true, true, true, true);
        emit ITaskManager.TaskUpdated(
            taskOpts[0].taskId,
            address(fundsHandler),
            State.Completed,
            block.timestamp
        );
        entryPoint.verifyAndCall(taskOpts, signature);
        WithdrawalInfo memory withdrawInfo = fundsHandler.getWithdrawal(msgSender, withdrawIndex);
        assertEq(
            abi.encodePacked(msgSender, CHAIN_ID, DEFAULT_AMOUNT - WITHDRAW_FEE),
            abi.encodePacked(withdrawInfo.userAddress, withdrawInfo.chainId, withdrawInfo.amount)
        );
        vm.stopPrank();
    }

    function test_WithdrawRevert() public {
        vm.startPrank(msgSender);
        // setup withdraw info
        // fail case: invalid amount
        withdrawTaskParams[0].amount = 0; // invalid amount
        vm.expectRevert(IFundsHandler.InvalidAmount.selector);
        fundsHandler.submitWithdrawTask(withdrawTaskParams);

        // fail case: not enough to pay withdraw fee
        withdrawTaskParams[0].amount = WITHDRAW_FEE - 1; // invalid amount
        vm.expectRevert("Insufficient balance to pay fee");
        fundsHandler.submitWithdrawTask(withdrawTaskParams);

        // fail case: invalid deposit address
        withdrawTaskParams[0].amount = 1 ether;
        withdrawTaskParams[0].toAddress = "";
        vm.expectRevert(IFundsHandler.InvalidAddress.selector);
        fundsHandler.submitWithdrawTask(withdrawTaskParams);
        vm.stopPrank();
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
                amounts[i],
                bytes32(uint256(i))
            );
            taskOperations[i] = TaskOperation(
                i + 1,
                State.Pending,
                abi.encodeWithSelector(
                    fundsHandler.recordWithdrawal.selector,
                    msgSender,
                    CHAIN_ID,
                    TICKER,
                    DEPOSIT_ADDRESS,
                    amounts[i] - WITHDRAW_FEE,
                    WITHDRAW_FEE,
                    bytes32(uint256(i)),
                    uint256(320) + (32 * ((bytes(DEPOSIT_ADDRESS).length - 1) / 32))
                ),
                ""
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
            taskOperations[i].extraData = TestHelper.getPaddedString("txHash");
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
            assertEq(withdrawalInfo.amount, amounts[i] - WITHDRAW_FEE);
        }
        vm.stopPrank();
    }

    function testFuzz_WithdrawFuzz(
        string calldata _toAddress,
        uint256 _amount,
        bytes32 _salt,
        string calldata _txHash
    ) public {
        vm.startPrank(msgSender);
        vm.assume(bytes(_toAddress).length > 0);
        vm.assume(_amount > MIN_DEFAULT_AMOUNT);
        vm.assume(_amount > WITHDRAW_FEE);
        vm.assume(bytes(_txHash).length > 0);
        // setup withdrawal info
        WithdrawalInfo[] memory tempWithdrawTaskParams = new WithdrawalInfo[](1);
        tempWithdrawTaskParams[0] = WithdrawalInfo(
            msgSender,
            CHAIN_ID,
            TICKER,
            _toAddress,
            _amount,
            _salt
        );
        fundsHandler.submitWithdrawTask(tempWithdrawTaskParams);

        // pending task
        taskOpts[0].state = State.Pending;
        taskOpts[0].initialCalldata = abi.encodeWithSelector(
            fundsHandler.recordWithdrawal.selector,
            msgSender,
            CHAIN_ID,
            TICKER,
            _toAddress,
            _amount - WITHDRAW_FEE,
            WITHDRAW_FEE,
            _salt,
            uint256(320) + (32 * ((bytes(_toAddress).length - 1) / 32))
        );
        signature = _generateOptSignature(taskOpts, tssKey);
        entryPoint.verifyAndCall(taskOpts, signature);

        // completed task
        taskOpts[0].state = State.Completed;
        taskOpts[0].extraData = TestHelper.getPaddedString(_txHash);
        signature = _generateOptSignature(taskOpts, tssKey);
        // check event and result
        vm.expectEmit(true, true, true, true);
        emit ITaskManager.TaskUpdated(
            taskOpts[0].taskId,
            address(fundsHandler),
            State.Completed,
            block.timestamp
        );
        entryPoint.verifyAndCall(taskOpts, signature);
        vm.stopPrank();
    }

    function test_Consolidate() public {
        vm.startPrank(msgSender);
        string memory fromAddr = "0xFromAddress";
        uint256 amount = 1 ether;
        string memory txHash = "consolidate_txHash";
        ConsolidateTaskParam[] memory consolidateParams = new ConsolidateTaskParam[](1);

        // empty from address
        consolidateParams[0] = ConsolidateTaskParam(
            "",
            TICKER,
            CHAIN_ID,
            amount,
            bytes32(uint256(0))
        );
        vm.expectRevert("Invalid address");
        fundsHandler.submitConsolidateTask(consolidateParams);

        // below minimum amount
        consolidateParams[0] = ConsolidateTaskParam(
            fromAddr,
            TICKER,
            CHAIN_ID,
            0,
            bytes32(uint256(0))
        );
        vm.expectRevert("Invalid amount");
        fundsHandler.submitConsolidateTask(consolidateParams);

        // correct amount
        consolidateParams[0] = ConsolidateTaskParam(
            fromAddr,
            TICKER,
            CHAIN_ID,
            amount,
            bytes32(uint256(0))
        );
        fundsHandler.submitConsolidateTask(consolidateParams);
        taskOpts[0].initialCalldata = abi.encodeWithSelector(
            fundsHandler.consolidate.selector,
            fromAddr,
            TICKER,
            CHAIN_ID,
            amount,
            bytes32(uint256(0)),
            uint256(256) // offset for address
        );
        taskOpts[0].extraData = TestHelper.getPaddedString(txHash);
        signature = _generateOptSignature(taskOpts, tssKey);

        vm.expectEmit(true, true, true, true);
        emit ITaskManager.TaskUpdated(
            taskOpts[0].taskId,
            address(fundsHandler),
            State.Completed,
            block.timestamp
        );
        entryPoint.verifyAndCall(taskOpts, signature);
        (
            string memory tempAddr,
            bytes32 tempTicker,
            uint64 tempChainId,
            uint256 tempAmount,

        ) = fundsHandler.consolidateRecords(TICKER, CHAIN_ID, 0);
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
        transferParams[0] = TransferParam(
            "",
            toAddr,
            TICKER,
            CHAIN_ID,
            amount,
            bytes32(uint256(0))
        );
        vm.expectRevert("Invalid address");
        fundsHandler.submitTransferTask(transferParams);

        // empty from address
        transferParams[0] = TransferParam(
            fromAddr,
            "",
            TICKER,
            CHAIN_ID,
            amount,
            bytes32(uint256(1))
        );
        vm.expectRevert("Invalid address");
        fundsHandler.submitTransferTask(transferParams);

        // below minimum amount
        transferParams[0] = TransferParam(
            fromAddr,
            toAddr,
            TICKER,
            CHAIN_ID,
            0,
            bytes32(uint256(2))
        );
        vm.expectRevert("Invalid amount");
        fundsHandler.submitTransferTask(transferParams);

        // correct amount
        transferParams[0] = TransferParam(
            fromAddr,
            toAddr,
            TICKER,
            CHAIN_ID,
            amount,
            bytes32(uint256(3))
        );
        fundsHandler.submitTransferTask(transferParams);
        console.log("fromAddr len", bytes(fromAddr).length);
        taskOpts[0].initialCalldata = abi.encodeWithSelector(
            fundsHandler.transfer.selector,
            fromAddr,
            toAddr,
            TICKER,
            CHAIN_ID,
            amount,
            bytes32(uint256(3)),
            uint256(352) // offset for address
        );
        taskOpts[0].extraData = TestHelper.getPaddedString(txHash);
        signature = _generateOptSignature(taskOpts, tssKey);

        vm.expectEmit(true, true, true, true);
        emit IFundsHandler.Transfer(TICKER, CHAIN_ID, fromAddr, toAddr, amount, txHash);
        entryPoint.verifyAndCall(taskOpts, signature);
        vm.stopPrank();
    }
}
