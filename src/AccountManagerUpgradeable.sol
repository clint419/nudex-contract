// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IAccountManager} from "./interfaces/IAccountManager.sol";

contract AccountManagerUpgradeable is IAccountManager, OwnableUpgradeable {
    mapping(bytes => string) public addressRecord;
    mapping(string depositAddress => mapping(Chain => address user)) public userMapping;

    // _owner: Voting Manager contract
    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
    }

    function getAddressRecord(
        address _user,
        uint256 _account,
        Chain _chain,
        uint256 _index
    ) external view returns (string memory) {
        return addressRecord[abi.encodePacked(_user, _account, _chain, _index)];
    }

    // register new deposit address for user
    function registerNewAddress(
        address _user,
        uint256 _account,
        Chain _chain,
        uint256 _index,
        string calldata _address
    ) external onlyOwner returns (bytes memory) {
        return _registerNewAddress(_user, _account, _chain, _index, _address);
    }

    function registerNewAddress_Batch(
        address[] calldata _users,
        uint256[] calldata _accounts,
        Chain[] calldata _chains,
        uint256[] calldata _indexs,
        string[] calldata _addresses
    ) external onlyOwner returns (bytes[] memory) {
        require(
            _users.length == _accounts.length &&
                _chains.length == _accounts.length &&
                _chains.length == _indexs.length &&
                _addresses.length == _indexs.length,
            InvalidInput()
        );
        bytes[] memory results = new bytes[](_users.length);
        for (uint16 i; i < _users.length; ++i) {
            results[i] = _registerNewAddress(
                _users[i],
                _accounts[i],
                _chains[i],
                _indexs[i],
                _addresses[i]
            );
        }
        return results;
    }

    function _registerNewAddress(
        address _user,
        uint256 _account,
        Chain _chain,
        uint256 _index,
        string calldata _address
    ) internal returns (bytes memory) {
        require(bytes(_address).length != 0, InvalidAddress());
        require(_account > 10000, InvalidAccountNumber(_account));
        require(
            bytes(addressRecord[abi.encodePacked(_user, _account, _chain, _index)]).length == 0,
            RegisteredAccount(
                _user,
                addressRecord[abi.encodePacked(_user, _account, _chain, _index)]
            )
        );
        addressRecord[abi.encodePacked(_user, _account, _chain, _index)] = _address;
        userMapping[_address][_chain] = _user;
        emit AddressRegistered(_user, _account, _chain, _index, _address);
        return abi.encodePacked(true, uint8(1), _user, _account, _chain, _index);
    }
}
