pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {NuvoDao, TimelockController} from "../src/dao/NuvoDao.sol";

contract DAOTest is BaseTest {
    NuvoDao public dao;

    function setUp() public override {
        super.setUp();

        address[] memory empty = new address[](0);
        TimelockController timelock = new TimelockController(2 days, empty, empty, msgSender);

        dao = new NuvoDao(nuvoToken, timelock);
    }
}
