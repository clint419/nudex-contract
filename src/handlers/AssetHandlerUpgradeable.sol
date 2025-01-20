// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAssetHandler, AssetParam, TransferParam, ConsolidateTaskParam, NudexAsset, TokenInfo} from "../interfaces/IAssetHandler.sol";
import {HandlerBase} from "./HandlerBase.sol";

contract AssetHandlerUpgradeable is IAssetHandler, HandlerBase {
    bytes32 public constant FUNDS_ROLE = keccak256("FUNDS_ROLE");

    // Mapping from asset identifiers to their details
    bytes32[] public assetTickerList;
    mapping(bytes32 ticker => NudexAsset) public nudexAssets;
    mapping(bytes32 ticker => uint64[] chainIds) public linkedTokenList;
    mapping(bytes32 ticker => mapping(uint64 chainId => TokenInfo)) public linkedTokens;
    mapping(bytes32 ticker => mapping(uint64 chainId => ConsolidateTaskParam[]))
        public consolidateRecords;

    modifier checkListing(bytes32 _ticker) {
        require(nudexAssets[_ticker].isListed, AssetNotListed(_ticker));
        _;
    }

    constructor(address _taskManager) HandlerBase(_taskManager) {}

    // _owner: EntryPoint contract
    function initialize(
        address _owner,
        address _entryPoint,
        address _submitter
    ) public initializer {
        __HandlerBase_init(_owner, _entryPoint, _submitter);
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
    function getAllLinkedTokens(bytes32 _ticker) external view returns (uint64[] memory) {
        return linkedTokenList[_ticker];
    }

    // Get the details of a linked token
    function getLinkedToken(
        bytes32 _ticker,
        uint64 _chainId
    ) external view returns (TokenInfo memory) {
        return linkedTokens[_ticker][_chainId];
    }

    // Submit a task to list a new asset
    function submitListAssetTask(
        bytes32[] calldata _tickers,
        AssetParam[] calldata _assetParams
    ) external onlyRole(SUBMITTER_ROLE) returns (uint64[] memory taskIds) {
        require(_tickers.length == _assetParams.length, "Mismatch data length");
        taskIds = new uint64[](_tickers.length);
        for (uint8 i; i < _tickers.length; i++) {
            require(!nudexAssets[_tickers[i]].isListed, "Asset already listed");
            taskIds[i] = taskManager.submitTask(
                msg.sender,
                abi.encodeWithSelector(this.listNewAsset.selector, _tickers[i], _assetParams[i])
            );
        }
    }

    // List a new asset
    function listNewAsset(
        bytes32 _ticker,
        AssetParam calldata _assetParam
    ) external onlyRole(ENTRYPOINT_ROLE) {
        require(!nudexAssets[_ticker].isListed, "Asset already listed");
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

    // TODO: add batch operation?
    // Submit a task to update an existing asset
    function submitAssetTask(
        bytes32 _ticker,
        bytes calldata _callData
    ) external onlyRole(SUBMITTER_ROLE) checkListing(_ticker) returns (uint64 taskId) {
        taskId = taskManager.submitTask(msg.sender, _callData);
        emit RequestUpdateAsset(taskId, _ticker, _callData);
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
            uint64 chainId = _tokenInfos[i].chainId;
            require(linkedTokens[_ticker][chainId].chainId == 0, "Linked Token");
            linkedTokens[_ticker][chainId] = _tokenInfos[i];
            linkedTokenList[_ticker].push(chainId);
        }
        emit LinkToken(_ticker, _tokenInfos);
    }

    // delete all linked tokens
    function resetlinkedToken(bytes32 _ticker) public onlyRole(ENTRYPOINT_ROLE) {
        uint64[] memory chainIds = linkedTokenList[_ticker];
        delete linkedTokenList[_ticker];
        for (uint32 i; i < chainIds.length; ++i) {
            linkedTokens[_ticker][chainIds[i]].isActive = false;
        }
        emit ResetLinkedToken(_ticker);
    }

    // switch token status to active or inactive
    function tokenSwitch(
        bytes32 _ticker,
        uint64 _chainId,
        bool _isActive
    ) external onlyRole(ENTRYPOINT_ROLE) {
        linkedTokens[_ticker][_chainId].isActive = _isActive;
        emit TokenSwitch(_ticker, _chainId, _isActive);
    }

    /**
     * @dev Submit a task to transfer asset
     * @param _params The task parameters
     * bytes32 ticker The asset ticker
     * uint64 chainId The chain id
     * string fromAddress The address to transfer from
     * string toAddress The address to transfer to
     * uint256 amount The amount to transfer
     */
    function submitTransferTask(
        TransferParam[] calldata _params
    ) external onlyRole(SUBMITTER_ROLE) returns (uint64[] memory taskIds) {
        taskIds = new uint64[](_params.length);
        for (uint8 i; i < _params.length; i++) {
            require(_params[i].amount > 0, InvalidAmount());
            uint256 fromAddrLength = bytes(_params[i].fromAddress).length;
            uint256 toAddrLength = bytes(_params[i].toAddress).length;
            require(fromAddrLength > 0 && toAddrLength > 0, InvalidAddress());

            taskIds[i] = taskManager.submitTask(
                msg.sender,
                abi.encodeWithSelector(
                    this.transfer.selector,
                    _params[i].fromAddress,
                    _params[i].toAddress,
                    _params[i].ticker,
                    _params[i].chainId,
                    _params[i].amount,
                    // offset for txHash
                    // @dev "-1" if it is exact 32 bytes it does not take one extra slot
                    uint256(320) +
                        (32 * ((fromAddrLength - 1) / 32)) +
                        (32 * ((toAddrLength - 1) / 32))
                )
            );
            emit RequestTransfer(taskIds[i], _params[i]);
        }
    }

    /**
     * @dev Transfer the asset
     */
    function transfer(
        string calldata _fromAddress,
        string calldata _toAddress,
        bytes32 _ticker,
        uint64 _chainId,
        uint256 _amount,
        string calldata _txHash
    ) external onlyRole(ENTRYPOINT_ROLE) checkListing(_ticker) {
        emit Transfer(_ticker, _chainId, _fromAddress, _toAddress, _amount, _txHash);
    }

    /**
     * @dev Submit a task to consolidate the asset
     * @param _params The task parameters
     * address[] fromAddr The addresses to consolidate from
     * bytes32 ticker The asset ticker
     * uint64 chainId The chain id
     * uint256 amount The amount to deposit
     */
    function submitConsolidateTask(
        ConsolidateTaskParam[] calldata _params
    ) external onlyRole(SUBMITTER_ROLE) returns (uint64[] memory taskIds) {
        taskIds = new uint64[](_params.length);
        for (uint8 i; i < _params.length; i++) {
            require(
                _params[i].amount >= nudexAssets[_params[i].ticker].minDepositAmount,
                InvalidAmount()
            );
            uint256 addrLength = bytes(_params[i].fromAddress).length;
            require(addrLength > 0, InvalidAddress());
            taskIds[i] = taskManager.submitTask(
                msg.sender,
                abi.encodeWithSelector(
                    this.consolidate.selector,
                    _params[i].fromAddress,
                    _params[i].ticker,
                    _params[i].chainId,
                    _params[i].amount,
                    // offset for txHash
                    // @dev "-1" if it is exact 32 bytes it does not take one extra slot
                    uint256(224) + (32 * ((addrLength - 1) / 32))
                )
            );
            emit RequestConsolidate(taskIds[i], _params[i]);
        }
    }

    /**
     * @dev Consolidate the token
     */
    function consolidate(
        string calldata _fromAddress,
        bytes32 _ticker,
        uint64 _chainId,
        uint256 _amount,
        string calldata _txHash
    ) external onlyRole(ENTRYPOINT_ROLE) checkListing(_ticker) {
        consolidateRecords[_ticker][_chainId].push(
            ConsolidateTaskParam(_fromAddress, _ticker, _chainId, _amount)
        );
        emit Consolidate(_ticker, _chainId, _fromAddress, _amount, _txHash);
    }

    /**
     * @dev Subtract balance from the token
     * @param _ticker The asset ticker
     * @param _chainId The chain id
     * @param _amount The amount to withdraw
     */
    function withdraw(
        bytes32 _ticker,
        uint64 _chainId,
        uint256 _amount
    ) external onlyRole(FUNDS_ROLE) checkListing(_ticker) {
        require(linkedTokens[_ticker][_chainId].isActive, "Inactive token");
        emit Withdraw(_ticker, _chainId, _amount);
    }
}
