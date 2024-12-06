pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {IParticipantHandler} from "../src/interfaces/IParticipantHandler.sol";

contract ParticipantTest is BaseTest {
    address public user;

    address public participant1;
    address public participant2;
    address public participantHandlerProxy;
    address public nextSubmitter;

    function setUp() public override {
        super.setUp();
        participant1 = makeAddr("participant1");
        participant2 = makeAddr("participant2");

        // stake for the initial participants
        vm.startPrank(participant1);
        nuvoToken.mint(participant1, 100 ether);
        nuvoToken.approve(address(nuvoLock), MIN_LOCK_AMOUNT);
        nuvoLock.lock(MIN_LOCK_AMOUNT, MIN_LOCK_PERIOD);
        vm.stopPrank();
        vm.startPrank(participant2);
        nuvoToken.mint(participant2, 100 ether);
        nuvoToken.approve(address(nuvoLock), MIN_LOCK_AMOUNT);
        nuvoLock.lock(MIN_LOCK_AMOUNT, MIN_LOCK_PERIOD);
        vm.stopPrank();

        participantHandlerProxy = _deployProxy(
            address(new ParticipantHandlerUpgradeable()),
            daoContract
        );
        participantHandler = ParticipantHandlerUpgradeable(participantHandlerProxy);
        address[] memory participants = new address[](2);
        participants[0] = msgSender;
        participants[1] = participant1;
        // must have at least 3 participants
        vm.expectRevert(IParticipantHandler.NotEnoughParticipant.selector);
        participantHandler.initialize(address(nuvoLock), vmProxy, participants);
        participants = new address[](3);
        participants[0] = msgSender;
        participants[1] = participant1;
        participants[2] = participant2;
        participantHandler.initialize(address(nuvoLock), vmProxy, participants);
        assertEq(participantHandler.getParticipants().length, 3);

        entryPoint = EntryPointUpgradeable(vmProxy);
        entryPoint.initialize(
            tssSigner, // tssSigner
            participantHandlerProxy, // participantHandler
            address(taskManager), // taskManager
            address(nuvoLock) // nuvoLock
        );
        assert(
            entryPoint.nextSubmitter() == msgSender ||
                entryPoint.nextSubmitter() == participant1 ||
                entryPoint.nextSubmitter() == participant2
        );
    }

    function test_AddParticipant() public {
        uint64 taskId = taskSubmitter.submitTask(_generateTaskContext());
        // create an eligible user
        address newParticipant = makeAddr("newParticipant");
        // fail: did not stake
        bytes memory callData = abi.encodeWithSelector(
            IParticipantHandler.addParticipant.selector,
            newParticipant
        );
        Operation[] memory opts = new Operation[](1);
        opts[0] = Operation(participantHandlerProxy, State.Completed, taskId, callData);
        bytes memory signature = _generateSignature(opts, tssKey);
        nextSubmitter = entryPoint.nextSubmitter();
        vm.expectEmit(true, true, true, true);
        emit IEntryPoint.OperationFailed(
            abi.encodeWithSelector(IParticipantHandler.NotEligible.selector, newParticipant)
        );
        vm.prank(nextSubmitter);
        entryPoint.verifyAndCall(opts, signature);

        vm.startPrank(newParticipant);
        nuvoToken.mint(newParticipant, 100 ether);
        nuvoToken.approve(address(nuvoLock), MIN_LOCK_AMOUNT);
        nuvoLock.lock(MIN_LOCK_AMOUNT, MIN_LOCK_PERIOD);
        vm.stopPrank();

        // fail: only owner
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                thisAddr
            )
        );
        participantHandler.addParticipant(newParticipant);

        // successfully add new user
        taskId = taskSubmitter.submitTask(_generateTaskContext());
        callData = abi.encodeWithSelector(
            IParticipantHandler.addParticipant.selector,
            newParticipant
        );
        opts[0] = Operation(participantHandlerProxy, State.Completed, taskId, callData);
        signature = _generateSignature(opts, tssKey);
        vm.prank(entryPoint.nextSubmitter());
        vm.expectEmit(true, true, true, true);
        emit IParticipantHandler.ParticipantAdded(newParticipant);
        entryPoint.verifyAndCall(opts, signature);

        // fail: adding the same user again
        taskId = taskSubmitter.submitTask(_generateTaskContext());
        opts[0] = Operation(participantHandlerProxy, State.Completed, taskId, callData);
        signature = _generateSignature(opts, tssKey);
        nextSubmitter = entryPoint.nextSubmitter();
        vm.prank(nextSubmitter);
        vm.expectEmit(true, true, true, true);
        emit IEntryPoint.OperationFailed(
            abi.encodeWithSelector(IParticipantHandler.AlreadyParticipant.selector, newParticipant)
        );
        entryPoint.verifyAndCall(opts, signature);
    }

    function test_RemoveParticipant() public {
        // add one valid partcipant
        address newParticipant = makeAddr("newParticipant");
        _addParticipant(newParticipant);

        // remove the added user
        uint64 taskId = taskSubmitter.submitTask(_generateTaskContext());
        bytes memory callData = abi.encodeWithSelector(
            IParticipantHandler.removeParticipant.selector,
            newParticipant
        );
        Operation[] memory opts = new Operation[](1);
        opts[0] = Operation(participantHandlerProxy, State.Completed, taskId, callData);
        bytes memory signature = _generateSignature(opts, tssKey);
        vm.prank(entryPoint.nextSubmitter());
        vm.expectEmit(true, true, true, true);
        emit IParticipantHandler.ParticipantRemoved(newParticipant);
        entryPoint.verifyAndCall(opts, signature);
    }

    function test_RemoveParticipantRevert() public {
        uint64 taskId = taskSubmitter.submitTask(_generateTaskContext());
        // fail: cannot remove user when there is only 3 participant left
        bytes memory callData = abi.encodeWithSelector(
            IParticipantHandler.removeParticipant.selector,
            msgSender
        );
        Operation[] memory opts = new Operation[](1);
        opts[0] = Operation(participantHandlerProxy, State.Completed, taskId, callData);
        bytes memory signature = _generateSignature(opts, tssKey);
        vm.prank(entryPoint.nextSubmitter());
        vm.expectEmit(true, true, true, true);
        emit IEntryPoint.OperationFailed(
            abi.encodeWithSelector(IParticipantHandler.NotEnoughParticipant.selector)
        );
        entryPoint.verifyAndCall(opts, signature);

        // add one valid partcipant
        address newParticipant = makeAddr("newParticipant");
        _addParticipant(newParticipant);

        // fail: remove a non-participant user
        taskId = taskSubmitter.submitTask(_generateTaskContext());
        callData = abi.encodeWithSelector(IParticipantHandler.removeParticipant.selector, thisAddr);
        opts[0] = Operation(participantHandlerProxy, State.Completed, taskId, callData);
        signature = _generateSignature(opts, tssKey);
        nextSubmitter = entryPoint.nextSubmitter();
        vm.expectEmit(true, true, true, true);
        emit IEntryPoint.OperationFailed(
            abi.encodeWithSelector(IParticipantHandler.NotParticipant.selector, thisAddr)
        );
        vm.prank(nextSubmitter);
        entryPoint.verifyAndCall(opts, signature);
    }

    function test_massAddAndRemove() public {
        uint8 initNumOfParticipant = 3;
        address[] memory newParticipants = new address[](20);
        for (uint8 i; i < 20; ++i) {
            newParticipants[i] = _addParticipant(makeAddr(UintToString.uint256ToString(i)));
            assertEq(participantHandler.getParticipants().length, initNumOfParticipant + i + 1);
        }
        assertEq(participantHandler.getParticipants().length, 23);
        initNumOfParticipant = 23;
        uint64 taskId;
        bytes memory callData;
        Operation[] memory opts = new Operation[](20);
        for (uint8 i; i < 20; ++i) {
            // removing a participant
            taskId = taskSubmitter.submitTask(_generateTaskContext());
            callData = abi.encodeWithSelector(
                IParticipantHandler.removeParticipant.selector,
                newParticipants[i]
            );
            opts[i] = Operation(participantHandlerProxy, State.Completed, taskId, callData);
        }
        bytes memory signature = _generateSignature(opts, tssKey);
        nextSubmitter = entryPoint.nextSubmitter();
        vm.prank(nextSubmitter);
        entryPoint.verifyAndCall(opts, signature);
        assertEq(participantHandler.getParticipants().length, 3);
    }

    function _addParticipant(address _newParticipant) internal returns (address) {
        uint64 taskId = taskSubmitter.submitTask(_generateTaskContext());
        // create an eligible user
        nuvoToken.mint(_newParticipant, 100 ether);
        vm.startPrank(_newParticipant);
        nuvoToken.approve(address(nuvoLock), MIN_LOCK_AMOUNT);
        nuvoLock.lock(MIN_LOCK_AMOUNT, MIN_LOCK_PERIOD);
        vm.stopPrank();

        // add new user through entryPoint
        bytes memory callData = abi.encodeWithSelector(
            IParticipantHandler.addParticipant.selector,
            _newParticipant
        );
        Operation[] memory opts = new Operation[](1);
        opts[0] = Operation(participantHandlerProxy, State.Completed, taskId, callData);
        bytes memory signature = _generateSignature(opts, tssKey);
        vm.prank(entryPoint.nextSubmitter());
        entryPoint.verifyAndCall(opts, signature);
        return _newParticipant;
    }
}
