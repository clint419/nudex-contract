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
    bytes32 salt;
}

struct TransferParam {
    string fromAddress;
    string toAddress;
    bytes32 ticker;
    uint64 chainId;
    uint256 amount;
    bytes32 salt;
}

struct ConsolidateTaskParam {
    string fromAddress;
    bytes32 ticker;
    uint64 chainId;
    uint256 amount;
    bytes32 salt;
}

interface IFundsHandler {
    event RequestDeposit(uint64 taskId, DepositInfo depositInfo);
    event RequestWithdrawal(uint64 taskId, WithdrawalInfo withdrawalInfo);
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
    event WithdrawFee(
        address indexed userAddress,
        uint64 indexed chainId,
        bytes32 indexed ticker,
        uint256 feeAmount,
        bytes32 salt
    );

    event RequestTransfer(uint64[] taskIds, TransferParam[] params);
    event Transfer(
        bytes32 indexed ticker,
        uint64 indexed chainId,
        string fromAddress,
        string toAddress,
        uint256 amount,
        string txHash
    );
    event RequestConsolidate(uint64[] taskIds, ConsolidateTaskParam[] params);
    event Consolidate(
        bytes32 indexed ticker,
        uint64 indexed chainId,
        string fromAddress,
        uint256 amount,
        string txHash
    );

    error InvalidAmount();
    error InvalidInput();
    error InvalidAddress();

    function recordDeposit(DepositInfo calldata _param) external;

    function recordWithdrawal(
        address _userAddress,
        uint64 _chainId,
        bytes32 _ticker,
        string calldata _toAddress,
        uint256 _amount,
        uint256 _withdrawFee,
        bytes32 _salt,
        string calldata _txHash
    ) external;

    function getDeposits(address depositAddress) external view returns (DepositInfo[] memory);
    function getWithdrawals(address depositAddress) external view returns (WithdrawalInfo[] memory);
}
