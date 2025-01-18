// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAccountHandler, AddressCategory, AccountRegistrationTaskParam} from "../interfaces/IAccountHandler.sol";
import {HandlerBase} from "./HandlerBase.sol";

contract AccountHandlerUpgradeable is IAccountHandler, HandlerBase {
    mapping(bytes32 => string) public addressRecord;
    mapping(address userAddress => uint32 userAccount) public userAccounts;
    mapping(string depositAddress => mapping(AddressCategory => address account))
        public userMapping;

    constructor(address _taskManager) HandlerBase(_taskManager) {}

    // _owner: EntryPoint contract
    function initialize(
        address _owner,
        address _entryPoint,
        address _submitter
    ) public initializer {
        __HandlerBase_init(_owner, _entryPoint, _submitter);
    }

    /**
     * @dev Get registered address record.
     * @param _account Account number, must be greater than 10000.
     * @param _chain The chain type of the address.
     * @param _index The index of address.
     */
    function getAddressRecord(
        uint32 _account,
        AddressCategory _chain,
        uint32 _index
    ) external view returns (string memory) {
        return addressRecord[keccak256(abi.encodePacked(_account, _chain, _index))];
    }

    /**
     * @dev Submit a task to register new deposit address for user account.
     * @param _params The task parameters
     * address userAddr The EVM address of the user.
     * uint32 account The account number, must be greater than 10000.
     * AddressCategory chain The chain type of the address.
     * uint32 index The index of address.
     */
    function submitRegisterTask(
        AccountRegistrationTaskParam[] calldata _params
    ) external onlyRole(SUBMITTER_ROLE) returns (uint64[] memory taskIds) {
        taskIds = new uint64[](_params.length);
        AccountRegistrationTaskParam memory param;
        for (uint8 i; i < _params.length; i++) {
            param = _params[i];
            require(param.userAddr != address(0), InvalidUserAddress());
            require(param.account > 10000, InvalidAccountNumber(param.account));
            require(
                userAccounts[param.userAddr] == 0 || userAccounts[param.userAddr] == param.account,
                MismatchedAccount(userAccounts[param.userAddr])
            );
            require(
                bytes(
                    addressRecord[
                        keccak256(abi.encodePacked(param.account, param.chain, param.index))
                    ]
                ).length == 0,
                RegisteredAccount(
                    param.account,
                    addressRecord[
                        keccak256(abi.encodePacked(param.account, param.chain, param.index))
                    ]
                )
            );

            taskIds[i] = taskManager.submitTask(
                msg.sender,
                abi.encodeWithSelector(
                    this.registerNewAddress.selector,
                    param.userAddr,
                    param.account,
                    param.chain,
                    param.index
                )
            );
            emit RequestRegisterAddress(taskIds[i], param);
        }
    }

    /**
     * @dev Register new deposit address for user account.
     * @param _userAddr The EVM address of the user.
     * @param _account Account number, must be greater than 10000.
     * @param _chain The chain type of the address.
     * @param _index The index of address.
     * @param _address The registering address.
     */
    function registerNewAddress(
        address _userAddr,
        uint32 _account,
        AddressCategory _chain,
        uint32 _index,
        string calldata _address
    ) external onlyRole(ENTRYPOINT_ROLE) returns (bytes memory) {
        require(bytes(_address).length > 0, InvalidAddress());
        if (userAccounts[_userAddr] == 0) {
            userAccounts[_userAddr] = _account;
        }
        userMapping[_address][_chain] = _userAddr;
        addressRecord[keccak256(abi.encodePacked(_account, _chain, _index))] = _address;
        emit AddressRegistered(_userAddr, _account, _chain, _index, _address);
        return abi.encodePacked(uint8(1), _account, _chain, _index, _address);
    }
}
