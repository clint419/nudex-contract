// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

enum AddressCategory {
    BTC,
    EVM,
    SOL,
    SUI,
    EVM_TSS
}

struct AccountRegistrationTaskParam {
    address userAddr;
    uint32 account;
    AddressCategory chain;
    uint32 index;
}

interface IAccountHandler {
    // events
    event RequestRegisterAddress(
        address indexed userAddr,
        uint32 indexed account,
        AddressCategory indexed chain,
        uint32 index
    );
    event AddressRegistered(
        address userAddr,
        uint256 indexed account,
        AddressCategory indexed chain,
        uint256 indexed index,
        string newAddress
    );

    // errors
    error InvalidAddress();
    error InvalidUserAddress();
    error InvalidAccountNumber(uint);
    error InvalidInput();
    error MismatchedAccount(uint32);
    error RegisteredAccount(uint256, string);

    function addressRecord(bytes32 _input) external view returns (string memory);

    function userMapping(
        string calldata _addr,
        AddressCategory _chain
    ) external view returns (address);

    function getAddressRecord(
        uint32 _account,
        AddressCategory _chain,
        uint32 _index
    ) external view returns (string memory);

    function registerNewAddress(
        address _userAddr,
        uint32 _account,
        AddressCategory _chain,
        uint32 _index,
        string calldata _address
    ) external returns (bytes memory);
}
