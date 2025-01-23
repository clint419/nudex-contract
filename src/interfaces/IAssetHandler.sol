// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

struct AssetParam {
    uint8 decimals;
    bool depositEnabled;
    bool withdrawalEnabled;
    uint256 minDepositAmount;
    uint256 minWithdrawAmount;
    string assetAlias; // Common name of the asset
}

struct TransferParam {
    string fromAddress;
    string toAddress;
    bytes32 ticker;
    uint64 chainId;
    uint256 amount;
}

struct ConsolidateTaskParam {
    string fromAddress;
    bytes32 ticker;
    uint64 chainId;
    uint256 amount;
}

struct NudexAsset {
    uint32 listIndex;
    uint8 decimals;
    bool depositEnabled;
    bool withdrawalEnabled;
    bool isListed; // Whether the asset is listed
    uint32 createdTime;
    uint32 updatedTime;
    uint256 minDepositAmount;
    uint256 minWithdrawAmount;
    string assetAlias; // Common name of the asset
}

struct TokenInfo {
    uint64 chainId; // Chain ID for EVM-based assets, or specific IDs for BTC/Ordinal
    bool isActive;
    uint8 decimals;
    string contractAddress; // Address for ERC20, Inscription, or 0x0 for BTC/Ordinal/Native token
    string symbol;
    uint256 withdrawFee;
}

struct Pair {
    bytes32 assetA;
    bytes32 assetB;
    uint8 state; // TODO: add enum
    uint8 pairType; // TODO: add enum
    uint8 decimals;
    uint8 priceDecimals;
    uint32 listedTime;
    uint32 activeTime;
    uint256 maxTradeBaseToken;
    uint256 minTradeBaseToken;
    uint256 maxTradeQuoteToken;
    uint256 minTradeQuoteToken;
}

interface IAssetHandler {
    // events
    event RequestUpdateAsset(uint64 taskId, bytes32 indexed ticker, bytes callData);
    event AssetListed(bytes32 indexed ticker, AssetParam assetParam);
    event AssetUpdated(bytes32 indexed ticker, AssetParam assetParam);
    event AssetDelisted(bytes32 indexed ticker);
    event LinkToken(bytes32 indexed ticker, TokenInfo[] tokens);
    event TokenUpdated(bytes32 indexed ticker, uint64 indexed chainId, TokenInfo token);
    event ResetLinkedToken(bytes32 indexed ticker);
    event TokenSwitch(bytes32 indexed ticker, uint64 indexed chainId, bool isActive);

    event RequestTransfer(uint64 taskId, TransferParam param);
    event Transfer(
        bytes32 indexed ticker,
        uint64 indexed chainId,
        string fromAddress,
        string toAddress,
        uint256 amount,
        string txHash
    );
    event RequestConsolidate(uint64 taskId, ConsolidateTaskParam param);
    event Consolidate(
        bytes32 indexed ticker,
        uint64 indexed chainId,
        string fromAddress,
        uint256 amount,
        string txHash
    );
    event Withdraw(bytes32 indexed ticker, uint64 indexed chainId, uint256 amount);

    // errors
    error AssetNotListed(bytes32 ticker);
    error InvalidAddress();
    error InvalidAmount();

    // Check if an asset is listed
    function isAssetListed(bytes32 _ticker) external view returns (bool);

    // Get the details of an asset
    function getAssetDetails(bytes32 _ticker) external view returns (NudexAsset memory);

    // Get the list of all listed assets
    function getAllAssets() external view returns (bytes32[] memory);

    function withdraw(bytes32 _ticker, uint64 _chainId, uint256 _amount) external;
}
