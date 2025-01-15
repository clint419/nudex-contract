pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {NuvoDao, TimelockController} from "../src/dao/NuvoDao.sol";

contract DAOTest is BaseTest {
    NuvoDao public dao;

    function setUp() public override {
        super.setUp();

        address[] memory executor = new address[](1);
        executor[0] = msgSender;
        TimelockController timelock = new TimelockController(1 days, executor, executor, msgSender);

        dao = new NuvoDao(nuvoToken, timelock);
    }

    function test_General() public {
        vm.skip(true);
        assertEq(dao.votingDelay(), 0);
        assertEq(dao.votingPeriod(), 3600);
        assertEq(dao.proposalThreshold(), 1);

        // 1. Create a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(dao);

        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;

        // Example of calling a function on the NuvoDao contract itself
        bytes[] memory calldatas = new bytes[](1);
        // calldatas[0] = abi.encodeWithSignature("setProposalTestValue(uint256)", 42);

        // Propose
        vm.startPrank(msgSender);
        uint256 proposalId = dao.propose(targets, values, calldatas, "transfer funds");
        vm.stopPrank();

        // 2. Move forward in time to pass voting delay
        // vm.roll(block.number + dao.votingDelay() + 1);
        skip(1 days);

        // 3. Cast votes
        vm.startPrank(msgSender);
        dao.castVote(proposalId, 1); // For
        vm.stopPrank();

        // 4. Move forward in time to pass voting period
        vm.roll(block.number + dao.votingPeriod() + 1);

        // Proposal should now be "Succeeded"
        // 5. Queue the proposal
        dao.queue(targets, values, calldatas, keccak256(bytes("transfer funds")));

        // 6. Execute the proposal
        dao.execute(targets, values, calldatas, keccak256(bytes("transfer funds")));

        // Check if the proposal succeeded in changing state
        // (Adjust this to match the actual function in your contract)
        // uint256 newValue = dao.proposalTestValue();
        // assertEq(newValue, 42, "Proposal was not executed properly");
    }
}
