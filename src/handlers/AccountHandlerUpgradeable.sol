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
        bytes32[] memory dataHash = new bytes32[](_params.length);
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

            dataHash[i] = keccak256(
                abi.encodeWithSelector(
                    this.registerNewAddress.selector,
                    param.userAddr,
                    param.account,
                    param.chain,
                    param.index,
                    uint256(160) // offset for address
                )
            );
        }
        taskIds = taskManager.submitTaskBatch(msg.sender, dataHash);
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
    ) external onlyRole(ENTRYPOINT_ROLE) {
        require(bytes(_address).length > 0, InvalidAddress());
        bytes32 hash = keccak256(abi.encodePacked(_account, _chain, _index));
        require(
            bytes(addressRecord[hash]).length == 0,
            RegisteredAccount(_account, addressRecord[hash])
        );

        // check user address => account binding
        if (userAccounts[_userAddr] == 0) {
            userAccounts[_userAddr] = _account;
        } else {
            require(
                userAccounts[_userAddr] == _account,
                MismatchedAccount(userAccounts[_userAddr])
            );
        }

        addressRecord[hash] = _address;
        userMapping[_address][_chain] = _userAddr;
    }
}
