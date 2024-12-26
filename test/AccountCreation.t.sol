pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {AccountHandlerUpgradeable} from "../src/handlers/AccountHandlerUpgradeable.sol";
import {IAccountHandler} from "../src/interfaces/IAccountHandler.sol";
import {ITaskManager, State} from "../src/interfaces/ITaskManager.sol";

contract AccountCreationTest is BaseTest {
    uint256 constant DEFAULT_ACCOUNT = 10001;

    string public depositAddress;

    AccountHandlerUpgradeable public accountHandler;
    address public amProxy;

    function setUp() public override {
        super.setUp();
        depositAddress = "new_address";

        // deploy accountHandler
        amProxy = _deployProxy(
            address(new AccountHandlerUpgradeable(address(taskManager))),
            daoContract
        );
        accountHandler = AccountHandlerUpgradeable(amProxy);
        accountHandler.initialize(daoContract, vmProxy, msgSender);
        assertTrue(accountHandler.hasRole(ENTRYPOINT_ROLE, vmProxy));

        // assign handlers
        handlers.push(amProxy);
        taskManager.initialize(daoContract, vmProxy, handlers);
    }

    function test_Create() public {
        vm.startPrank(msgSender);
        // submit task
        taskOpts[0].taskId = accountHandler.submitRegisterTask(
            msgSender,
            DEFAULT_ACCOUNT,
            IAccountHandler.AddressCategory.BTC,
            0
        );
        taskOpts[0].extraData = offsetDepositString(depositAddress);
        bytes memory signature = _generateOptSignature(taskOpts, tssKey);
        entryPoint.verifyAndCall(taskOpts, signature);

        // check mappings|reverseMapping
        assertEq(
            accountHandler.getAddressRecord(
                DEFAULT_ACCOUNT,
                IAccountHandler.AddressCategory.BTC,
                uint(0)
            ),
            depositAddress
        );
        assertEq(
            accountHandler.addressRecord(
                abi.encodePacked(DEFAULT_ACCOUNT, IAccountHandler.AddressCategory.BTC, uint(0))
            ),
            depositAddress
        );
        assertEq(
            accountHandler.userMapping(depositAddress, IAccountHandler.AddressCategory.BTC),
            DEFAULT_ACCOUNT
        );
        assertEq(uint8(taskManager.getTaskState(taskOpts[0].taskId)), uint8(State.Completed));

        // fail: already registered
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccountHandler.RegisteredAccount.selector,
                DEFAULT_ACCOUNT,
                depositAddress
            )
        );
        taskOpts[0].taskId = accountHandler.submitRegisterTask(
            msgSender,
            DEFAULT_ACCOUNT,
            IAccountHandler.AddressCategory.BTC,
            0
        );
        vm.stopPrank();
    }

    function test_TaskRevert() public {
        vm.startPrank(msgSender);
        // fail case: user address as address zero
        vm.expectRevert(IAccountHandler.InvalidUserAddress.selector);
        accountHandler.submitRegisterTask(
            address(0),
            DEFAULT_ACCOUNT,
            IAccountHandler.AddressCategory.BTC,
            0
        );

        // fail case: account number less than 10000
        uint256 invalidAccountNum = uint256(9999);
        vm.expectRevert(
            abi.encodeWithSelector(IAccountHandler.InvalidAccountNumber.selector, invalidAccountNum)
        );
        accountHandler.submitRegisterTask(
            msgSender,
            invalidAccountNum,
            IAccountHandler.AddressCategory.BTC,
            0
        );
        vm.stopPrank();

        // fail case: deposit address as address zero
        vm.prank(vmProxy);
        vm.expectRevert(IAccountHandler.InvalidAddress.selector);
        accountHandler.registerNewAddress(
            msgSender,
            DEFAULT_ACCOUNT,
            IAccountHandler.AddressCategory.BTC,
            0,
            ""
        );
    }

    function testFuzz_SubmitTaskFuzz(
        uint256 _account,
        uint8 _chain,
        uint256 _index,
        string calldata _address
    ) public {
        vm.assume(_account < 10000000);
        vm.assume(_chain < 3);
        vm.assume(bytes(_address).length > 0);
        IAccountHandler.AddressCategory chain = IAccountHandler.AddressCategory(_chain);
        vm.startPrank(msgSender);
        if (_account > 10000) {
            accountHandler.submitRegisterTask(msgSender, _account, chain, _index);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(IAccountHandler.InvalidAccountNumber.selector, _account)
            );
            accountHandler.submitRegisterTask(msgSender, _account, chain, _index);
        }
        vm.stopPrank();
    }

    function offsetDepositString(string memory _address) internal pure returns (bytes memory) {
        bytes memory depositAddrData = abi.encode(_address);
        depositAddrData[31] = bytes1(uint8(160));
        return depositAddrData;
    }
}
