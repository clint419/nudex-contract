pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {Proxy} from "../src/Proxy.sol";
import {AccountManagerUpgradeable} from "../src/AccountManagerUpgradeable.sol";
import {IAccountManager} from "../src/interfaces/IAccountManager.sol";
import {NuDexOperationsUpgradeable} from "../src/NuDexOperationsUpgradeable.sol";
import {INuDexOperations} from "../src/interfaces/INuDexOperations.sol";
import {VotingManagerUpgradeable} from "../src/VotingManagerUpgradeable.sol";

import {MockParticipantManager} from "../src/mocks/MockParticipantManager.sol";
import {MockNuvoLockUpgradeable} from "../src/mocks/MockNuvoLockUpgradeable.sol";

contract AccountCreation is BaseTest {
    address public depositAddress;

    AccountManagerUpgradeable public accountManager;
    NuDexOperationsUpgradeable public nuDexOperations;
    VotingManagerUpgradeable public votingManager;
    MockParticipantManager public participantManager;
    MockNuvoLockUpgradeable public nuvoLock;

    uint public v;

    function setUp() public override {
        super.setUp();
        depositAddress = makeAddr("new_address");

        // deploy mock contract
        participantManager = new MockParticipantManager(owner);
        nuvoLock = new MockNuvoLockUpgradeable();

        // deploy votingManager
        address vmLogic = address(new VotingManagerUpgradeable());
        address vmProxy = address(new TransparentUpgradeableProxy(vmLogic, daoContract, ""));

        // deploy nuDexOperations
        address operationLogic = address(new NuDexOperationsUpgradeable());
        address operationProxy = address(
            new TransparentUpgradeableProxy(operationLogic, daoContract, "")
        );
        nuDexOperations = NuDexOperationsUpgradeable(operationProxy);
        nuDexOperations.initialize(address(participantManager), vmProxy);
        assertEq(nuDexOperations.owner(), vmProxy);

        // deploy accountManager
        address amLogic = address(new AccountManagerUpgradeable());
        address amProxy = address(new TransparentUpgradeableProxy(amLogic, daoContract, ""));
        accountManager = AccountManagerUpgradeable(amProxy);
        accountManager.initialize(vmProxy);
        assertEq(accountManager.owner(), vmProxy);

        votingManager = VotingManagerUpgradeable(vmProxy);
        votingManager.initialize(
            amProxy,
            address(0),
            address(0),
            address(participantManager),
            operationProxy,
            address(nuvoLock),
            owner
        );
        assertEq(address(votingManager.accountManager()), address(accountManager));
    }

    function test_Create() public {
        vm.startPrank(owner);
        uint256 taskId = nuDexOperations.nextTaskId();
        string memory taskDescription = "--- encoded task string ---";
        vm.expectEmit(true, true, true, true);
        emit INuDexOperations.TaskSubmitted(taskId, taskDescription, owner);
        nuDexOperations.submitTask(taskDescription);
        assertEq(taskId, nuDexOperations.nextTaskId() - 1);

        // process after tss picked up the task
        bytes memory encodedParams = abi.encodePacked(
            owner,
            uint(10001),
            IAccountManager.Chain.BTC,
            uint(0),
            depositAddress
        );
        bytes memory signature = generateSignature(encodedParams, privKey);
        votingManager.registerAccount(
            owner,
            10001,
            IAccountManager.Chain.BTC,
            0,
            depositAddress,
            signature
        );

        // check mappings|reverseMapping
        assertEq(
            accountManager.addressRecord(
                abi.encodePacked(owner, uint(10001), IAccountManager.Chain.BTC, uint(0))
            ),
            depositAddress
        );
        assertEq(accountManager.userMapping(depositAddress, IAccountManager.Chain.BTC), owner);
        vm.expectRevert("already registered");
        votingManager.registerAccount(
            owner,
            10001,
            IAccountManager.Chain.BTC,
            0,
            depositAddress,
            signature
        );

        // finialize task
        bytes memory taskResult = "--- encoded task result ---";
        encodedParams = abi.encodePacked(taskId, taskResult);
        signature = generateSignature(encodedParams, privKey);
        vm.expectEmit(true, true, true, true);
        emit INuDexOperations.TaskCompleted(taskId, owner, block.timestamp, taskResult);
        votingManager.submitTaskReceipt(taskId, taskResult, signature);
        vm.stopPrank();
    }

    function test_CreateRevert() public {
        // fail case: msg.sender not the owner
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                thisAddr
            )
        );
        accountManager.registerNewAddress(
            owner,
            10001,
            IAccountManager.Chain.BTC,
            0,
            depositAddress
        );

        // fail case: account number less than 10000
        bytes memory encodedParams = abi.encodePacked(
            owner,
            uint(9999),
            IAccountManager.Chain.BTC,
            uint(0),
            depositAddress
        );
        bytes memory signature = generateSignature(encodedParams, privKey);
        vm.prank(owner);
        vm.expectRevert("invalid account");
        votingManager.registerAccount(
            owner,
            9999,
            IAccountManager.Chain.BTC,
            0,
            depositAddress,
            signature
        );
    }
}
