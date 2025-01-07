// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAccountHandler} from "../interfaces/IAccountHandler.sol";
import {HandlerBase} from "./HandlerBase.sol";

contract AccountHandlerUpgradeable is IAccountHandler, HandlerBase {
    // TODO: use bytes32 for key
    mapping(bytes => string) public addressRecord;
    mapping(string depositAddress => mapping(AddressCategory => uint256 account))
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
        // TODO: kecaak256 input
        return addressRecord[abi.encodePacked(_account, _chain, _index)];
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
            bytes(addressRecord[abi.encodePacked(_account, _chain, _index)]).length == 0,
            RegisteredAccount(_account, addressRecord[abi.encodePacked(_account, _chain, _index)])
        );
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
        addressRecord[abi.encodePacked(_account, _chain, _index)] = _address;
        userMapping[_address][_chain] = _account;
        emit AddressRegistered(_userAddr, _account, _chain, _index, _address);
        return abi.encodePacked(uint8(1), _account, _chain, _index, _address);
    }
}
