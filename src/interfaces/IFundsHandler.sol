// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

struct DepositTaskParam {
    address userAddress;
    string depositAddress;
    bytes32 ticker;
    bytes32 chainId;
    uint256 amount;
    bytes32 txHash;
    uint256 blockHeight;
    uint256 logIndex;
}

struct WithdrawTaskParam {
    address userAddress;
    string depositAddress;
    bytes32 ticker;
    bytes32 chainId;
    uint256 amount;
}

interface IFundsHandler {
    struct DepositInfo {
        string depositAddress;
        bytes32 ticker;
        bytes32 chainId;
        uint256 amount;
    }

    struct WithdrawalInfo {
        string depositAddress;
        bytes32 ticker;
        bytes32 chainId;
        uint256 amount;
    }

    event NewPauseState(bytes32 indexed condition, bool indexed newState);
    event DepositRecorded(
        string depositAddress,
        bytes32 indexed ticker,
        bytes32 indexed chainId,
        uint256 amount,
        bytes32 txHash,
        uint256 blockHeight,
        uint256 logIndex
    );
    event WithdrawalRecorded(
        string depositAddress,
        bytes32 indexed ticker,
        bytes32 indexed chainId,
        uint256 amount
    );

    error InvalidAmount();
    error InvalidInput();
    error InvalidAddress();
    error Paused();

    function recordDeposit(DepositTaskParam calldata _param) external returns (bytes memory);

    function recordWithdrawal(WithdrawTaskParam calldata _param) external returns (bytes memory);

    function getDeposits(
        string calldata depositAddress
    ) external view returns (DepositInfo[] memory);
    function getWithdrawals(
        string calldata depositAddress
    ) external view returns (WithdrawalInfo[] memory);
}
