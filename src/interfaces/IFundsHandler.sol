// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

struct DepositInfo {
    address userAddress;
    string depositAddress;
    bytes32 ticker;
    bytes32 chainId;
    uint256 amount;
    uint256 blockHeight;
    uint256 logIndex;
}

struct WithdrawalInfo {
    address userAddress;
    string depositAddress;
    bytes32 ticker;
    bytes32 chainId;
    uint256 amount;
}

interface IFundsHandler {
    event NewPauseState(bytes32 indexed condition, bool indexed newState);
    event DepositRecorded(
        address indexed userAddress,
        string depositAddress,
        bytes32 indexed ticker,
        bytes32 indexed chainId,
        uint256 amount,
        uint256 blockHeight,
        uint256 logIndex
    );
    event WithdrawalRecorded(
        address indexed userAddress,
        string depositAddress,
        bytes32 indexed ticker,
        bytes32 indexed chainId,
        uint256 amount
    );

    error InvalidAmount();
    error InvalidInput();
    error InvalidAddress();
    error Paused();

    function recordDeposit(DepositInfo calldata _param) external returns (bytes memory);

    function recordWithdrawal(WithdrawalInfo calldata _param) external returns (bytes memory);

    function getDeposits(
        string calldata depositAddress
    ) external view returns (DepositInfo[] memory);
    function getWithdrawals(
        string calldata depositAddress
    ) external view returns (WithdrawalInfo[] memory);
}
