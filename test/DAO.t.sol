pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {NuvoDao, TimelockController} from "../src/dao/NuvoDao.sol";

contract DAOTest is BaseTest {
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    TimelockController public timelock;
    NuvoDao public dao;

    function setUp() public override {
        super.setUp();

        address[] memory executor = new address[](1);
        executor[0] = msgSender;
        timelock = new TimelockController(1 days, executor, executor, msgSender);
        payable(timelock).transfer(100 ether);

        dao = new NuvoDao(nuvoToken, timelock);
        vm.startPrank(msgSender);
        timelock.grantRole(PROPOSER_ROLE, address(dao));
        timelock.grantRole(EXECUTOR_ROLE, address(dao));
        timelock.grantRole(CANCELLER_ROLE, address(dao));

        assertEq(dao.votingDelay(), 0);
        assertEq(dao.votingPeriod(), 3600);
        assertEq(dao.proposalThreshold(), 1);

        nuvoToken.delegate(msgSender);
        vm.roll(100);
    }

    function test_FundingProposal() public {
        uint256 initialTargetBalance = msgSender.balance;
        uint256 initialReservedBalance = address(timelock).balance;
        uint256 fundingAmount = 1 ether;
        // 1. Create a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(msgSender);

        uint256[] memory values = new uint256[](1);
        values[0] = fundingAmount;

        // Example of calling a function on the NuvoDao contract itself
        bytes[] memory calldatas = new bytes[](1);
        // calldatas[0] = abi.encodeWithSignature("setProposalTestValue(uint256)", 42);

        // Description
        string memory description = "transfer funds";

        // Propose
        vm.startPrank(msgSender);
        uint256 proposalId = dao.propose(targets, values, calldatas, description);
        vm.stopPrank();

        // 2. Move forward in time to pass voting delay
        vm.roll(block.number + dao.votingDelay() + 1);

        // 3. Cast votes
        vm.startPrank(msgSender);
        dao.castVote(proposalId, 1); // For
        vm.stopPrank();

        // 4. Move forward in time to pass voting period
        vm.roll(block.number + dao.votingPeriod() + 1);

        // Proposal should now be "Succeeded"
        // 5. Queue the proposal
        dao.queue(targets, values, calldatas, keccak256(bytes(description)));

        // 6. Wait for delay
        skip(1 days);

        // 7. Execute the proposal
        bytes32 taskId = timelock.hashOperationBatch(
            targets,
            values,
            calldatas,
            0,
            bytes20(address(dao)) ^ keccak256(bytes(description))
        );
        dao.execute(targets, values, calldatas, keccak256(bytes(description)));

        // Check if the proposal succeeded in changing state
        uint256 finalTargetBalance = msgSender.balance;
        uint256 finalReservedBalance = address(timelock).balance;
        assertEq(finalTargetBalance, initialTargetBalance + fundingAmount);
        assertEq(finalReservedBalance, initialReservedBalance - fundingAmount);
    }
}
