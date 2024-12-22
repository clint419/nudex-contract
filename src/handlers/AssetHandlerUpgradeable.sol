// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IAssetHandler, AssetParam, NudexAsset, TokenInfo} from "../interfaces/IAssetHandler.sol";
import {ITaskManager} from "../interfaces/ITaskManager.sol";

contract AssetHandlerUpgradeable is IAssetHandler, AccessControlUpgradeable {
    bytes32 public constant ENTRYPOINT_ROLE = keccak256("ENTRYPOINT_ROLE");
    bytes32 public constant FUNDS_ROLE = keccak256("FUNDS_ROLE");
    bytes32 public constant SUBMITTER_ROLE = keccak256("SUBMITTER_ROLE");
    ITaskManager public immutable taskManager;

    // Mapping from asset identifiers to their details
    bytes32[] public assetTickerList;
    mapping(bytes32 ticker => NudexAsset) public nudexAssets;
    mapping(bytes32 ticker => bytes32[] chainIds) public linkedTokenList;
    mapping(bytes32 ticker => mapping(bytes32 chainId => TokenInfo)) public linkedTokens;

    modifier checkListing(bytes32 _ticker) {
        require(nudexAssets[_ticker].isListed, AssetNotListed(_ticker));
        _;
    }

    constructor(address _taskManager) {
        taskManager = ITaskManager(_taskManager);
    }

    // _owner: EntryPoint contract
    function initialize(
        address _owner,
        address _entryPoint,
        address _submitter
    ) public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(ENTRYPOINT_ROLE, _entryPoint);
        _grantRole(SUBMITTER_ROLE, _submitter);
    }

    // Check if an asset is listed
    function isAssetListed(bytes32 _ticker) external view returns (bool) {
        return nudexAssets[_ticker].isListed;
    }

    // Get the details of an asset
    function getAssetDetails(
        bytes32 _ticker
    ) external view checkListing(_ticker) returns (NudexAsset memory) {
        return nudexAssets[_ticker];
    }

    // Get the list of all listed assets
    function getAllAssets() external view returns (bytes32[] memory) {
        return assetTickerList;
    }

    // Get the list of all listed assets
    function getAllLinkedTokens(bytes32 _ticker) external view returns (bytes32[] memory) {
        return linkedTokenList[_ticker];
    }

    function getLinkedToken(
        bytes32 _ticker,
        bytes32 _chainId
    ) external view returns (TokenInfo memory) {
        return linkedTokens[_ticker][_chainId];
    }

    function submitListAssetTask(
        bytes32 _ticker,
        AssetParam calldata _assetParam
    ) external onlyRole(SUBMITTER_ROLE) returns (uint64) {
        require(!nudexAssets[_ticker].isListed, "Asset already listed");
        return
            taskManager.submitTask(
                msg.sender,
                abi.encodeWithSelector(this.listNewAsset.selector, _ticker, _assetParam)
            );
    }

    // List a new asset
    function listNewAsset(
        bytes32 _ticker,
        AssetParam calldata _assetParam
    ) external onlyRole(ENTRYPOINT_ROLE) {
        NudexAsset storage tempNudexAsset = nudexAssets[_ticker];
        // update listed assets
        tempNudexAsset.listIndex = uint32(assetTickerList.length);
        tempNudexAsset.isListed = true;
        tempNudexAsset.createdTime = uint32(block.timestamp);
        tempNudexAsset.updatedTime = uint32(block.timestamp);

        // info from param
        tempNudexAsset.decimals = _assetParam.decimals;
        tempNudexAsset.depositEnabled = _assetParam.depositEnabled;
        tempNudexAsset.withdrawalEnabled = _assetParam.withdrawalEnabled;
        tempNudexAsset.minDepositAmount = _assetParam.minDepositAmount;
        tempNudexAsset.minWithdrawAmount = _assetParam.minWithdrawAmount;
        tempNudexAsset.assetAlias = _assetParam.assetAlias;

        assetTickerList.push(_ticker);
        emit AssetListed(_ticker, _assetParam);
    }

    function submitAssetTask(
        bytes32 _ticker,
        bytes calldata _callData
    ) external onlyRole(SUBMITTER_ROLE) checkListing(_ticker) returns (uint64) {
        return taskManager.submitTask(msg.sender, _callData);
    }

    // Update listed asset
    function updateAsset(
        bytes32 _ticker,
        AssetParam calldata _assetParam
    ) external onlyRole(ENTRYPOINT_ROLE) {
        NudexAsset storage tempNudexAsset = nudexAssets[_ticker];
        // update listed assets
        tempNudexAsset.updatedTime = uint32(block.timestamp);

        // info from param
        tempNudexAsset.decimals = _assetParam.decimals;
        tempNudexAsset.depositEnabled = _assetParam.depositEnabled;
        tempNudexAsset.withdrawalEnabled = _assetParam.withdrawalEnabled;
        tempNudexAsset.minDepositAmount = _assetParam.minDepositAmount;
        tempNudexAsset.minWithdrawAmount = _assetParam.minWithdrawAmount;
        tempNudexAsset.assetAlias = _assetParam.assetAlias;

        emit AssetUpdated(_ticker, _assetParam);
    }

    // Delist an existing asset
    function delistAsset(bytes32 _ticker) external onlyRole(ENTRYPOINT_ROLE) {
        NudexAsset storage tempNudexAsset = nudexAssets[_ticker];
        uint32 listIndex = tempNudexAsset.listIndex;
        // TODO: do we need to reset linked tokens?
        // resetlinkedToken(_ticker);
        tempNudexAsset.isListed = false;
        tempNudexAsset.updatedTime = uint32(block.timestamp);
        assetTickerList[listIndex] = assetTickerList[assetTickerList.length - 1];
        nudexAssets[assetTickerList[listIndex]].listIndex = listIndex;
        assetTickerList.pop();
        emit AssetDelisted(_ticker);
    }

    // add on-chain token to the asset
    function linkToken(
        bytes32 _ticker,
        TokenInfo[] calldata _tokenInfos
    ) external onlyRole(ENTRYPOINT_ROLE) {
        for (uint8 i; i < _tokenInfos.length; ++i) {
            bytes32 chainId = _tokenInfos[i].chainId;
            require(linkedTokens[_ticker][chainId].chainId == 0, "Linked Token");
            linkedTokens[_ticker][chainId] = _tokenInfos[i];
            linkedTokenList[_ticker].push(chainId);
        }
        emit LinkToken(_ticker, _tokenInfos);
    }

    // delete all linked tokens
    function resetlinkedToken(bytes32 _ticker) public onlyRole(ENTRYPOINT_ROLE) {
        bytes32[] memory chainIds = linkedTokenList[_ticker];
        delete linkedTokenList[_ticker];
        for (uint32 i; i < chainIds.length; ++i) {
            linkedTokens[_ticker][chainIds[i]].isActive = false;
        }
        emit ResetLinkedToken(_ticker);
    }

    // switch token status
    function tokenSwitch(
        bytes32 _ticker,
        bytes32 _chainId,
        bool _isActive
    ) external onlyRole(ENTRYPOINT_ROLE) {
        linkedTokens[_ticker][_chainId].isActive = _isActive;
        emit TokenSwitch(_ticker, _chainId, _isActive);
    }

    function submitConsolidateTask(
        bytes32 _ticker,
        bytes32 _chainId,
        uint256 _amount
    ) external onlyRole(SUBMITTER_ROLE) checkListing(_ticker) returns (uint64) {
        return
            taskManager.submitTask(
                msg.sender,
                abi.encodeWithSelector(this.consolidate.selector, _ticker, _chainId, _amount)
            );
    }

    function consolidate(
        bytes32 _ticker,
        bytes32 _chainId,
        uint256 _amount
    ) external onlyRole(ENTRYPOINT_ROLE) {
        linkedTokens[_ticker][_chainId].balance += _amount;
        emit Consolidate(_ticker, _chainId, _amount);
    }

    function withdraw(
        bytes32 _ticker,
        bytes32 _chainId,
        uint256 _amount
    ) external onlyRole(FUNDS_ROLE) checkListing(_ticker) {
        require(linkedTokens[_ticker][_chainId].isActive, "Inactive token");
        require(
            linkedTokens[_ticker][_chainId].balance >= _amount,
            InsufficientBalance(_ticker, _chainId)
        );
        linkedTokens[_ticker][_chainId].balance -= _amount;
        emit Withdraw(_ticker, _chainId, _amount);
    }
}
