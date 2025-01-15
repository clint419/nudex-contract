// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

struct DepositInfo {
    address userAddress;
    uint64 chainId;
    bytes32 ticker;
    string depositAddress;
    uint256 amount;
    string txHash;
    uint256 blockHeight;
    uint256 logIndex;
}

struct WithdrawalInfo {
    address userAddress;
    uint64 chainId;
    bytes32 ticker;
    string toAddress;
    uint256 amount;
}

interface IFundsHandler {
    event NewPauseState(bytes32 indexed condition, bool indexed newState);
    event DepositRequested(DepositInfo depositInfo);
    event WithdrawalRequested(WithdrawalInfo withdrawalInfo);
    event DepositRecorded(
        address indexed userAddress,
        bytes32 indexed ticker,
        uint64 indexed chainId,
        string depositAddress,
        uint256 amount,
        string txHash,
        uint256 blockHeight,
        uint256 logIndex
    );
    event WithdrawalRecorded(
        address indexed userAddress,
        bytes32 indexed ticker,
        uint64 indexed chainId,
        string toAddress,
        uint256 amount,
        string txHash
    );

    error InvalidAmount();
    error InvalidInput();
    error InvalidAddress();
    error Paused();

    function recordDeposit(DepositInfo calldata _param) external returns (bytes memory);

    function recordWithdrawal(
        address _userAddress,
        uint64 _chainId,
        bytes32 _ticker,
        string calldata _toAddress,
        uint256 _amount,
        string calldata _txHash
    ) external returns (bytes memory);

    function getDeposits(address depositAddress) external view returns (DepositInfo[] memory);
    function getWithdrawals(address depositAddress) external view returns (WithdrawalInfo[] memory);
}
