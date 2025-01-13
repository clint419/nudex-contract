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
        assertEq(dao.votingDelay(), 0);
        assertEq(dao.votingPeriod(), 3600);
        assertEq(dao.proposalThreshold(), 1);
    }
}
