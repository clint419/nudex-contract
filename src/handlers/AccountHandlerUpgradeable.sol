// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAccountHandler} from "../interfaces/IAccountHandler.sol";
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
     * @param _userAddr The EVM address of the user.
     * @param _account Account number, must be greater than 10000.
     * @param _chain The chain type of the address.
     * @param _index The index of address.
     */
    function submitRegisterTask(
        address _userAddr,
        uint32 _account,
        AddressCategory _chain,
        uint32 _index
    ) external onlyRole(SUBMITTER_ROLE) returns (uint64) {
        require(_userAddr != address(0), InvalidUserAddress());
        require(_account > 10000, InvalidAccountNumber(_account));
        require(
            userAccounts[_userAddr] == 0 || userAccounts[_userAddr] == _account,
            MismatchedAccount(userAccounts[_userAddr])
        );
        require(
            bytes(addressRecord[keccak256(abi.encodePacked(_account, _chain, _index))]).length == 0,
            RegisteredAccount(
                _account,
                addressRecord[keccak256(abi.encodePacked(_account, _chain, _index))]
            )
        );
        emit RequestRegisterAddress(_userAddr, _account, _chain, _index);
        return
            taskManager.submitTask(
                msg.sender,
                abi.encodeWithSelector(
                    this.registerNewAddress.selector,
                    _userAddr,
                    _account,
                    _chain,
                    _index
                )
            );
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
