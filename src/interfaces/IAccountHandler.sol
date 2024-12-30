// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAccountHandler {
    enum AddressCategory {
        BTC,
        EVM,
        SOL,
        SUI,
        EVM_TSS
    }

    event AddressRegistered(
        address userAddr,
        uint256 indexed account,
        AddressCategory indexed chain,
        uint256 indexed index,
        string newAddress
    );

    error InvalidAddress();
    error InvalidUserAddress();
    error InvalidAccountNumber(uint);
    error InvalidInput();
    error RegisteredAccount(uint256, string);

    function addressRecord(bytes calldata _input) external view returns (string memory);

    function userMapping(
        string calldata _addr,
        AddressCategory _chain
    ) external view returns (uint256);

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
