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

struct ConsolidateTaskParam {
    string fromAddress;
    bytes32 ticker;
    bytes32 chainId;
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
    bytes32 chainId; // Chain ID for EVM-based assets, or specific IDs for BTC/Ordinal
    bool isActive;
    uint8 decimals;
    string contractAddress; // Address for ERC20, Inscription, or 0x0 for BTC/Ordinal/Native token
    string symbol;
    uint256 withdrawFee;
    // uint256 balance; // TODO: do we need to store balance?
}

interface IAssetHandler {
    // events
    event AssetListed(bytes32 indexed ticker, AssetParam assetParam);
    event AssetUpdated(bytes32 indexed ticker, AssetParam assetParam);
    event AssetDelisted(bytes32 indexed ticker);
    event LinkToken(bytes32 indexed ticker, TokenInfo[] tokens);
    event ResetLinkedToken(bytes32 indexed ticker);
    event TokenSwitch(bytes32 indexed ticker, bytes32 indexed chainId, bool isActive);
    event Consolidate(
        bytes32 indexed ticker,
        bytes32 indexed chainId,
        string fromAddress,
        uint256 amount
    );
    event Withdraw(bytes32 indexed ticker, bytes32 indexed chainId, uint256 amount);

    // errors
    error AssetNotListed(bytes32 ticker);

    // Check if an asset is listed
    function isAssetListed(bytes32 _ticker) external view returns (bool);

    // Get the details of an asset
    function getAssetDetails(bytes32 _ticker) external view returns (NudexAsset memory);

    // Get the list of all listed assets
    function getAllAssets() external view returns (bytes32[] memory);

    function withdraw(bytes32 _ticker, bytes32 _chainId, uint256 _amount) external;
}
