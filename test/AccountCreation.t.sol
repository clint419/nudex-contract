pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {TestHelper} from "./utils/TestHelper.sol";

import {AccountHandlerUpgradeable} from "../src/handlers/AccountHandlerUpgradeable.sol";
import {IAccountHandler, AddressCategory, AccountRegistrationTaskParam} from "../src/interfaces/IAccountHandler.sol";
import {ITaskManager, State} from "../src/interfaces/ITaskManager.sol";

contract AccountCreationTest is BaseTest {
    uint32 constant DEFAULT_ACCOUNT = 10001;

    string public depositAddress;

    AccountHandlerUpgradeable public accountHandler;

    function setUp() public override {
        super.setUp();
        depositAddress = "new_address";

        // deploy accountHandler
        address accountHandlerProxy = _deployProxy(
            address(new AccountHandlerUpgradeable(address(taskManager))),
            daoContract
        );
        accountHandler = AccountHandlerUpgradeable(accountHandlerProxy);
        accountHandler.initialize(daoContract, entryPointProxy, msgSender);
        assertTrue(accountHandler.hasRole(ENTRYPOINT_ROLE, entryPointProxy));

        // assign handlers
        handlers.push(accountHandlerProxy);
        taskManager.initialize(daoContract, entryPointProxy, handlers);
    }

    function test_Create() public {
        vm.startPrank(msgSender);
        // submit task
        AccountRegistrationTaskParam[] memory taskParams = new AccountRegistrationTaskParam[](1);
        taskParams[0] = AccountRegistrationTaskParam(
            msgSender,
            DEFAULT_ACCOUNT,
            AddressCategory.BTC,
            0
        );
        accountHandler.submitRegisterTask(taskParams);
        taskOpts[0].extraData = TestHelper.getPaddedString(depositAddress);
        signature = _generateOptSignature(taskOpts, tssKey);
        entryPoint.verifyAndCall(taskOpts, signature);

        // check mappings|reverseMapping
        assertEq(
            accountHandler.getAddressRecord(DEFAULT_ACCOUNT, AddressCategory.BTC, uint32(0)),
            depositAddress
        );
        assertEq(
            accountHandler.addressRecord(
                keccak256(abi.encodePacked(DEFAULT_ACCOUNT, AddressCategory.BTC, uint32(0)))
            ),
            depositAddress
        );
        assertEq(accountHandler.userMapping(depositAddress, AddressCategory.BTC), msgSender);
        assertEq(uint8(taskManager.getTaskState(taskOpts[0].taskId)), uint8(State.Completed));

        // fail: already registered
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccountHandler.RegisteredAccount.selector,
                DEFAULT_ACCOUNT,
                depositAddress
            )
        );
        accountHandler.submitRegisterTask(taskParams);

        // fail: mismatch account
        taskParams[0] = AccountRegistrationTaskParam(
            msgSender,
            DEFAULT_ACCOUNT + 1,
            AddressCategory.BTC,
            0
        );
        vm.expectRevert(
            abi.encodeWithSelector(IAccountHandler.MismatchedAccount.selector, DEFAULT_ACCOUNT)
        );
        accountHandler.submitRegisterTask(taskParams);
        vm.stopPrank();
    }

    function test_TaskRevert() public {
        vm.startPrank(msgSender);
        AccountRegistrationTaskParam[] memory taskParams = new AccountRegistrationTaskParam[](1);
        taskParams[0] = AccountRegistrationTaskParam(
            address(0),
            DEFAULT_ACCOUNT,
            AddressCategory.BTC,
            0
        );
        // fail case: user address as address zero
        vm.expectRevert(IAccountHandler.InvalidUserAddress.selector);
        accountHandler.submitRegisterTask(taskParams);

        // fail case: account number less than 10000
        uint32 invalidAccountNum = uint32(9999);
        taskParams[0] = AccountRegistrationTaskParam(
            msgSender,
            invalidAccountNum,
            AddressCategory.BTC,
            0
        );
        vm.expectRevert(
            abi.encodeWithSelector(IAccountHandler.InvalidAccountNumber.selector, invalidAccountNum)
        );
        accountHandler.submitRegisterTask(taskParams);
        vm.stopPrank();

        // fail case: deposit address as address zero
        vm.prank(entryPointProxy);
        vm.expectRevert(IAccountHandler.InvalidAddress.selector);
        accountHandler.registerNewAddress(msgSender, DEFAULT_ACCOUNT, AddressCategory.BTC, 0, "");
    }

    function testFuzz_SubmitTaskFuzz(
        uint32 _account,
        uint8 _chain,
        uint32 _index,
        string calldata _address
    ) public {
        vm.assume(_account < 10000000);
        vm.assume(_chain < 3);
        vm.assume(bytes(_address).length > 0);
        AddressCategory chain = AddressCategory(_chain);
        vm.startPrank(msgSender);
        AccountRegistrationTaskParam[] memory taskParams = new AccountRegistrationTaskParam[](1);
        taskParams[0] = AccountRegistrationTaskParam(msgSender, _account, chain, _index);
        if (_account > 10000) {
            accountHandler.submitRegisterTask(taskParams);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(IAccountHandler.InvalidAccountNumber.selector, _account)
            );
            accountHandler.submitRegisterTask(taskParams);
        }
        vm.stopPrank();
    }
}
