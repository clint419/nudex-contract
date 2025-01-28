// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAssetHandler, AssetParam, TransferParam, ConsolidateTaskParam, NudexAsset, Pair, PairState, PairType, TokenInfo} from "../interfaces/IAssetHandler.sol";
import {HandlerBase} from "./HandlerBase.sol";

contract AssetHandlerUpgradeable is IAssetHandler, HandlerBase {
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");
    bytes32 public constant FUNDS_ROLE = keccak256("FUNDS_ROLE");

    // Mapping from asset identifiers to their details
    bytes32[] public assetTickerList;
    mapping(bytes32 ticker => NudexAsset) public nudexAssets;
    mapping(bytes32 ticker => uint64[] chainIds) public linkedTokenList;
    mapping(bytes32 ticker => mapping(uint64 chainId => TokenInfo)) public linkedTokens;
    mapping(bytes32 ticker => mapping(uint64 chainId => ConsolidateTaskParam[]))
        public consolidateRecords;

    Pair[] private pairs;
    mapping(bytes32 hashedPair => uint256 index) private assetPairIndex;

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
        _grantRole(DAO_ROLE, _owner);

        // push empty pair, reserving index 0 for empty pair
        pairs.push(Pair(0, 0, PairState.Inactive, PairType.Spot, 0, 0, 0, 0, 0, 0, 0, 0));
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

    // List a new asset
    function listNewAsset(
        bytes32 _ticker,
        AssetParam calldata _assetParam
    ) external onlyRole(DAO_ROLE) {
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

    function getPairInfo(bytes32 _assetA, bytes32 _assetB) external view returns (Pair memory) {
        return pairs[getPairIndex(_assetA, _assetB)];
    }

    function getPairIndex(bytes32 _assetA, bytes32 _assetB) public view returns (uint256) {
        if (_assetA < _assetB) {
            return assetPairIndex[_getPairHash(_assetA, _assetB)];
        }
        return assetPairIndex[_getPairHash(_assetB, _assetA)];
    }

    function _getPairHash(bytes32 _assetA, bytes32 _assetB) internal pure returns (bytes32) {
        if (_assetA < _assetB) {
            return keccak256(abi.encodePacked(_assetA, _assetB));
        }
        return keccak256(abi.encodePacked(_assetB, _assetA));
    }

    function addPair(Pair[] memory _pairs) external onlyRole(DAO_ROLE) {
        for (uint8 i; i < _pairs.length; i++) {
            require(nudexAssets[_pairs[i].assetA].isListed, AssetNotListed(_pairs[i].assetA));
            require(nudexAssets[_pairs[i].assetB].isListed, AssetNotListed(_pairs[i].assetB));

            uint256 index = pairs.length;
            if (_pairs[i].assetA < _pairs[i].assetB) {
                assetPairIndex[_getPairHash(_pairs[i].assetA, _pairs[i].assetB)] = index;
            } else {
                assetPairIndex[_getPairHash(_pairs[i].assetB, _pairs[i].assetA)] = index;
            }

            _pairs[i].listedTime = uint32(block.timestamp);
            _pairs[i].activeTime = uint32(block.timestamp);
            pairs.push(_pairs[i]);
            emit PairAdded(_pairs[i], index);
        }
    }

    function removePair(bytes32 _assetA, bytes32 _assetB) external onlyRole(DAO_ROLE) {
        pairs[getPairIndex(_assetA, _assetB)] = pairs[pairs.length - 1];
        pairs.pop();
        assetPairIndex[_getPairHash(_assetA, _assetB)] = 0;
    }

    // Update listed asset
    function updateAsset(
        bytes32 _ticker,
        AssetParam calldata _assetParam
    ) external onlyRole(DAO_ROLE) checkListing(_ticker) {
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
    function delistAsset(bytes32 _ticker) external onlyRole(DAO_ROLE) checkListing(_ticker) {
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
    ) external onlyRole(DAO_ROLE) checkListing(_ticker) {
        for (uint8 i; i < _tokenInfos.length; ++i) {
            uint64 chainId = _tokenInfos[i].chainId;
            require(linkedTokens[_ticker][chainId].chainId == 0, "Linked Token");
            linkedTokens[_ticker][chainId] = _tokenInfos[i];
            linkedTokenList[_ticker].push(chainId);
        }
        emit LinkToken(_ticker, _tokenInfos);
    }

    function updateToken(
        bytes32 _ticker,
        TokenInfo calldata _tokenInfo
    ) external onlyRole(DAO_ROLE) checkListing(_ticker) {
        uint64 chainId = _tokenInfo.chainId;
        require(linkedTokens[_ticker][chainId].chainId != 0, "Token not linked");
        linkedTokens[_ticker][chainId] = _tokenInfo;
        emit TokenUpdated(_ticker, _tokenInfo);
    }

    // delete all linked tokens
    function resetlinkedToken(bytes32 _ticker) public onlyRole(DAO_ROLE) checkListing(_ticker) {
        uint64[] memory chainIds = linkedTokenList[_ticker];
        delete linkedTokenList[_ticker];
        for (uint32 i; i < chainIds.length; ++i) {
            delete linkedTokens[_ticker][chainIds[i]];
        }
        emit ResetLinkedToken(_ticker);
    }

    // switch token status to active or inactive
    function tokenSwitch(
        bytes32 _ticker,
        uint64 _chainId,
        bool _isActive
    ) external onlyRole(DAO_ROLE) checkListing(_ticker) {
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
            require(_params[i].amount > 0, "Invalid amount");
            uint256 fromAddrLength = bytes(_params[i].fromAddress).length;
            uint256 toAddrLength = bytes(_params[i].toAddress).length;
            require(fromAddrLength > 0 && toAddrLength > 0, "Invalid address");

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
                "Invalid amount"
            );
            uint256 addrLength = bytes(_params[i].fromAddress).length;
            require(addrLength > 0, "Invalid address");
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
