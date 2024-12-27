pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {AssetHandlerUpgradeable, AssetParam, TokenInfo} from "../src/handlers/AssetHandlerUpgradeable.sol";
import {FundsHandlerUpgradeable} from "../src/handlers/FundsHandlerUpgradeable.sol";
import {IFundsHandler} from "../src/interfaces/IFundsHandler.sol";
import {ITaskManager, State} from "../src/interfaces/ITaskManager.sol";

contract FundsTest is BaseTest {
    bytes32 public constant TICKER = "TOKEN_TICKER_18";
    bytes32 public constant FUNDS_ROLE = keccak256("FUNDS_ROLE");
    bytes32 public constant CHAIN_ID = 0;
    uint256 public constant MIN_DEPOSIT_AMOUNT = 50;
    uint256 public constant MIN_WITHDRAW_AMOUNT = 50;

    string public depositAddress;

    FundsHandlerUpgradeable public fundsHandler;

    address public dmProxy;

    function setUp() public override {
        super.setUp();
        depositAddress = "0xDepositAddress";

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
            MIN_DEPOSIT_AMOUNT,
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
            0,
            100 ether
        );
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
    }

    function test_Deposit() public {
        vm.startPrank(msgSender);
        // setup deposit info
        uint256 depositIndex = fundsHandler.getDeposits(depositAddress).length;
        assertEq(depositIndex, 0);
        bytes32 chainId = CHAIN_ID;
        uint256 depositAmount = 1 ether;
        taskOpts[0].taskId = fundsHandler.submitDepositTask(
            msgSender,
            depositAddress,
            TICKER,
            chainId,
            depositAmount
        );
        signature = _generateOptSignature(taskOpts, tssKey);
        // check event and result
        vm.expectEmit(true, true, true, true);
        emit IFundsHandler.DepositRecorded(depositAddress, TICKER, chainId, depositAmount);
        entryPoint.verifyAndCall(taskOpts, signature);

        IFundsHandler.DepositInfo memory depositInfo = fundsHandler.getDeposit(
            depositAddress,
            depositIndex
        );
        assertEq(
            abi.encodePacked(depositAddress, TICKER, chainId, depositAmount),
            abi.encodePacked(
                depositInfo.depositAddress,
                depositInfo.ticker,
                depositInfo.chainId,
                depositInfo.amount
            )
        );

        // second deposit
        // setup deposit info
        depositIndex = fundsHandler.getDeposits(depositAddress).length;
        assertEq(depositIndex, 1); // should have increased by 1
        chainId = bytes32(uint256(1));
        depositAmount = 5 ether;
        taskOpts[0].taskId = fundsHandler.submitDepositTask(
            msgSender,
            depositAddress,
            TICKER,
            chainId,
            depositAmount
        );
        signature = _generateOptSignature(taskOpts, tssKey);

        // check event and result
        vm.expectEmit(true, true, true, true);
        emit IFundsHandler.DepositRecorded(depositAddress, TICKER, chainId, depositAmount);
        entryPoint.verifyAndCall(taskOpts, signature);
        depositInfo = fundsHandler.getDeposit(depositAddress, depositIndex);
        assertEq(
            abi.encodePacked(depositAddress, TICKER, chainId, depositAmount),
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
        bytes32 chainId = CHAIN_ID;
        uint256 depositAmount = 0; // invalid amount
        // fail case: invalid amount
        vm.expectRevert(IFundsHandler.InvalidAmount.selector);
        taskOpts[0].taskId = fundsHandler.submitDepositTask(
            msgSender,
            depositAddress,
            TICKER,
            chainId,
            depositAmount
        );

        // fail case: invalid user address
        depositAmount = 1 ether;
        depositAddress = "";
        vm.expectRevert(IFundsHandler.InvalidAddress.selector);
        taskOpts[0].taskId = fundsHandler.submitDepositTask(
            msgSender,
            depositAddress,
            TICKER,
            chainId,
            depositAmount
        );
        vm.stopPrank();

        depositAddress = "0xDepositAddress";
        vm.prank(vmProxy);
        fundsHandler.setPauseState(TICKER, true);
        vm.expectRevert(IFundsHandler.Paused.selector);
        vm.prank(msgSender);
        taskOpts[0].taskId = fundsHandler.submitDepositTask(
            msgSender,
            depositAddress,
            TICKER,
            chainId,
            depositAmount
        );
    }

    function test_DepositBatch() public {
        vm.startPrank(msgSender);
        uint8 batchSize = 20;
        // setup deposit info
        TaskOperation[] memory taskOperations = new TaskOperation[](batchSize);
        string[] memory depositAddresses = new string[](batchSize);
        uint256[] memory amounts = new uint256[](batchSize);
        for (uint8 i; i < batchSize; ++i) {
            depositAddresses[i] = string(abi.encodePacked("depositAddress", i));
            amounts[i] = 1 ether;
            taskOperations[i] = TaskOperation(
                fundsHandler.submitDepositTask(
                    msgSender,
                    depositAddresses[i],
                    TICKER,
                    CHAIN_ID,
                    amounts[i]
                ),
                State.Pending,
                0,
                ""
            );
        }
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
        IFundsHandler.DepositInfo memory depositInfo;
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
        vm.assume(_amount > MIN_DEPOSIT_AMOUNT);
        // setup deposit info
        bytes32 chainId = CHAIN_ID;
        uint256 depositIndex = fundsHandler.getDeposits(_depositAddress).length;
        taskOpts[0].taskId = fundsHandler.submitDepositTask(
            msgSender,
            _depositAddress,
            TICKER,
            chainId,
            _amount
        );
        signature = _generateOptSignature(taskOpts, tssKey);

        // check event and result
        vm.expectEmit(true, true, true, true);
        emit IFundsHandler.DepositRecorded(_depositAddress, TICKER, chainId, _amount);
        entryPoint.verifyAndCall(taskOpts, signature);
        IFundsHandler.DepositInfo memory depositInfo = fundsHandler.getDeposit(
            _depositAddress,
            depositIndex
        );
        assertEq(
            abi.encodePacked(_depositAddress, TICKER, chainId, _amount),
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
        uint256 withdrawIndex = fundsHandler.getWithdrawals(depositAddress).length;
        assertEq(withdrawIndex, 0);
        bytes32 chainId = CHAIN_ID;
        uint256 withdrawAmount = 1 ether;
        taskOpts[0].taskId = fundsHandler.submitWithdrawTask(
            msgSender,
            depositAddress,
            TICKER,
            chainId,
            withdrawAmount
        );
        signature = _generateOptSignature(taskOpts, tssKey);
        // check event and result
        vm.expectEmit(true, true, true, true);
        emit IFundsHandler.WithdrawalRecorded(depositAddress, TICKER, chainId, withdrawAmount);
        entryPoint.verifyAndCall(taskOpts, signature);
        IFundsHandler.WithdrawalInfo memory withdrawInfo = fundsHandler.getWithdrawal(
            depositAddress,
            withdrawIndex
        );
        assertEq(
            abi.encodePacked(depositAddress, chainId, withdrawAmount),
            abi.encodePacked(withdrawInfo.depositAddress, withdrawInfo.chainId, withdrawInfo.amount)
        );
        vm.stopPrank();
    }

    function test_WithdrawRevert() public {
        vm.startPrank(msgSender);
        // setup withdraw info
        bytes32 chainId = CHAIN_ID;
        uint256 withdrawAmount = 0; // invalid amount
        // fail case: invalid amount
        vm.expectRevert(IFundsHandler.InvalidAmount.selector);
        taskOpts[0].taskId = fundsHandler.submitWithdrawTask(
            msgSender,
            depositAddress,
            TICKER,
            chainId,
            withdrawAmount
        );
        // fail case: invalid deposit address
        withdrawAmount = 1 ether;
        depositAddress = "";
        vm.expectRevert(IFundsHandler.InvalidAddress.selector);
        taskOpts[0].taskId = fundsHandler.submitWithdrawTask(
            msgSender,
            depositAddress,
            TICKER,
            chainId,
            withdrawAmount
        );
        vm.stopPrank();

        depositAddress = "0xDepositAddress";
        vm.prank(vmProxy);
        fundsHandler.setPauseState(TICKER, true);
        vm.expectRevert(IFundsHandler.Paused.selector);
        vm.prank(msgSender);
        taskOpts[0].taskId = fundsHandler.submitWithdrawTask(
            msgSender,
            depositAddress,
            TICKER,
            chainId,
            withdrawAmount
        );
    }

    function test_WithdrawBatch() public {
        vm.startPrank(msgSender);
        uint8 batchSize = 20;
        // setup withdraw info
        TaskOperation[] memory taskOperations = new TaskOperation[](batchSize);
        string[] memory depositAddresses = new string[](batchSize);
        uint256[] memory amounts = new uint256[](batchSize);
        for (uint16 i; i < batchSize; ++i) {
            depositAddresses[i] = string(abi.encodePacked("depositAddress", i));
            amounts[i] = 1 ether;
            taskOperations[i] = TaskOperation(
                fundsHandler.submitWithdrawTask(
                    msgSender,
                    depositAddresses[i],
                    TICKER,
                    CHAIN_ID,
                    amounts[i]
                ),
                State.Pending,
                0,
                ""
            );
        }
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
        IFundsHandler.WithdrawalInfo memory withdrawalInfo;
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
