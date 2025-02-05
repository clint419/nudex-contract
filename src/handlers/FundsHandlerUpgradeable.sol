// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {HandlerBase} from "./HandlerBase.sol";
import {IAssetHandler} from "../interfaces/IAssetHandler.sol";
import {IFundsHandler, DepositInfo, WithdrawalInfo, TransferParam, ConsolidateTaskParam} from "../interfaces/IFundsHandler.sol";
import {INIP20} from "../interfaces/INIP20.sol";

contract FundsHandlerUpgradeable is IFundsHandler, HandlerBase {
    IAssetHandler public immutable assetHandler;

    mapping(address userAddr => DepositInfo[]) public deposits;
    mapping(address userAddr => WithdrawalInfo[]) public withdrawals;
    mapping(bytes32 ticker => mapping(uint64 chainId => ConsolidateTaskParam[]))
        public consolidateRecords;

    constructor(address _assetHandler, address _taskManager) HandlerBase(_taskManager) {
        assetHandler = IAssetHandler(_assetHandler);
    }

    function initialize(
        address _owner,
        address _entryPoint,
        address _submitter
    ) public initializer {
        __HandlerBase_init(_owner, _entryPoint, _submitter);
    }

    modifier validateAsset(bytes32 _ticker, uint64 _chainId) {
        require(assetHandler.isAssetAllowed(_ticker, _chainId), "Not allowed");
        _;
    }

    /**
     * @dev Get all deposit records of user.
     */
    function getDeposits(address _userAddress) external view returns (DepositInfo[] memory) {
        return deposits[_userAddress];
    }

    /**
     * @dev Get n-th deposit record of user.
     */
    function getDeposit(
        address _userAddress,
        uint256 _index
    ) external view returns (DepositInfo memory) {
        return deposits[_userAddress][_index];
    }

    /**
     * @dev Get all withdraw records of user.
     */
    function getWithdrawals(address _userAddress) external view returns (WithdrawalInfo[] memory) {
        return withdrawals[_userAddress];
    }

    /**
     * @dev Get n-th withdraw record of user.
     */
    function getWithdrawal(
        address _userAddress,
        uint256 _index
    ) external view returns (WithdrawalInfo memory) {
        return withdrawals[_userAddress][_index];
    }

    /**
     * @dev Submit deposit task.
     * @param _params The task parameters.
     * userAddress The EVM address of the user.
     * depositAddress The deposit address assigned to the user.
     * ticker The ticker of the asset.
     * chainId The chain id of the asset.
     * amount The amount to deposit.
     */
    function submitDepositTask(
        DepositInfo[] calldata _params
    ) external onlyRole(SUBMITTER_ROLE) returns (uint64[] memory taskIds) {
        require(_params.length > 0, "FundsHandlerUpgradeable: empty input");
        taskIds = new uint64[](_params.length);
        bytes32[] memory dataHash = new bytes32[](_params.length);
        for (uint8 i; i < _params.length; i++) {
            // TODO: do we check for asset state here?
            require(
                _params[i].amount >=
                    assetHandler.getAssetDetails(_params[i].ticker).minDepositAmount,
                InvalidAmount()
            );
            require(bytes(_params[i].depositAddress).length > 0, InvalidAddress());
            dataHash[i] = keccak256(
                abi.encodeWithSelector(this.recordDeposit.selector, _params[i])
            );
            emit RequestDeposit(taskIds[i], _params[i]);
        }
        taskIds = taskManager.submitTaskBatch(msg.sender, dataHash);
    }

    /**
     * @dev Record deposit info.
     */
    function recordDeposit(
        DepositInfo calldata _param
    )
        external
        onlyRole(ENTRYPOINT_ROLE)
        validateAsset(_param.ticker, _param.chainId)
        returns (bytes memory)
    {
        deposits[_param.userAddress].push(_param);
        emit INIP20.NIP20TokenEvent_mintb(_param.userAddress, _param.ticker, _param.amount);
        emit DepositRecorded(
            _param.userAddress,
            _param.ticker,
            _param.chainId,
            _param.depositAddress,
            _param.amount,
            _param.txHash,
            _param.blockHeight,
            _param.logIndex
        );
        return abi.encode(uint8(1), _param);
    }

    /**
     * @dev Submit withdraw task.
     * @param _params The task parameters.
     * userAddress The EVM address of the user.
     * depositAddress The deposit address assigned to the user.
     * ticker The ticker of the asset.
     * chainId The chain id of the asset.
     * amount The amount to deposit.
     * salt The salt for withdrawal.
     */
    function submitWithdrawTask(
        WithdrawalInfo[] calldata _params
    ) external onlyRole(SUBMITTER_ROLE) returns (uint64[] memory taskIds) {
        require(_params.length > 0, "FundsHandlerUpgradeable: empty input");
        taskIds = new uint64[](_params.length);
        bytes32[] memory dataHash = new bytes32[](_params.length);
        for (uint8 i; i < _params.length; i++) {
            require(
                _params[i].amount >=
                    assetHandler.getAssetDetails(_params[i].ticker).minWithdrawAmount,
                InvalidAmount()
            );
            uint256 addrLength = bytes(_params[i].toAddress).length;
            require(addrLength > 0, InvalidAddress());
            emit INIP20.NIP20TokenEvent_burnb(
                _params[i].userAddress,
                _params[i].ticker,
                _params[i].amount
            );
            // TODO: withdraw fee
            // _params[i].amount -= fee;
            dataHash[i] = keccak256(
                abi.encodeWithSelector(
                    this.recordWithdrawal.selector,
                    _params[i].userAddress,
                    _params[i].chainId,
                    _params[i].ticker,
                    _params[i].toAddress,
                    _params[i].amount,
                    _params[i].salt,
                    // offset for txHash
                    // @dev "-1" if it is exact 32 bytes it does not take one extra slot
                    uint256(288) + (32 * ((addrLength - 1) / 32))
                )
            );
            emit RequestWithdrawal(taskIds[i], _params[i]);
        }
        taskIds = taskManager.submitTaskBatch(msg.sender, dataHash);
    }

    /**
     * @dev Record withdraw info.
     */
    function recordWithdrawal(
        address _userAddress,
        uint64 _chainId,
        bytes32 _ticker,
        string calldata _toAddress,
        uint256 _amount,
        bytes32 _salt,
        string calldata _txHash
    ) external onlyRole(ENTRYPOINT_ROLE) validateAsset(_ticker, _chainId) returns (bytes memory) {
        withdrawals[_userAddress].push(
            WithdrawalInfo(_userAddress, _chainId, _ticker, _toAddress, _amount, _salt)
        );
        // TODO: transfer withdraw fee
        // emit INIP20.NIP20TokenEvent_mintb(adminAddress, _param.ticker, withdrawFee);
        emit WithdrawalRecorded(_userAddress, _ticker, _chainId, _toAddress, _amount, _txHash);
        return abi.encode(uint8(1), _userAddress, _chainId, _ticker, _toAddress, _amount, _txHash);
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
        bytes32[] memory dataHash = new bytes32[](_params.length);
        for (uint8 i; i < _params.length; i++) {
            require(_params[i].amount > 0, "Invalid amount");
            uint256 fromAddrLength = bytes(_params[i].fromAddress).length;
            uint256 toAddrLength = bytes(_params[i].toAddress).length;
            require(fromAddrLength > 0 && toAddrLength > 0, "Invalid address");

            dataHash[i] = keccak256(
                abi.encodeWithSelector(
                    this.transfer.selector,
                    _params[i].fromAddress,
                    _params[i].toAddress,
                    _params[i].ticker,
                    _params[i].chainId,
                    _params[i].amount,
                    _params[i].salt,
                    // offset for txHash
                    // @dev "-1" if it is exact 32 bytes it does not take one extra slot
                    uint256(352) +
                        (32 * ((fromAddrLength - 1) / 32)) +
                        (32 * ((toAddrLength - 1) / 32))
                )
            );
        }
        taskIds = taskManager.submitTaskBatch(msg.sender, dataHash);
        emit RequestTransfer(taskIds, _params);
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
        bytes32 _salt,
        string calldata _txHash
    ) external onlyRole(ENTRYPOINT_ROLE) validateAsset(_ticker, _chainId) {
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
        bytes32[] memory dataHash = new bytes32[](_params.length);
        for (uint8 i; i < _params.length; i++) {
            require(
                _params[i].amount >=
                    assetHandler.getAssetDetails(_params[i].ticker).minDepositAmount,
                "Invalid amount"
            );
            uint256 addrLength = bytes(_params[i].fromAddress).length;
            require(addrLength > 0, "Invalid address");
            dataHash[i] = keccak256(
                abi.encodeWithSelector(
                    this.consolidate.selector,
                    _params[i].fromAddress,
                    _params[i].ticker,
                    _params[i].chainId,
                    _params[i].amount,
                    _params[i].salt,
                    // offset for txHash
                    // @dev "-1" if it is exact 32 bytes it does not take one extra slot
                    uint256(256) + (32 * ((addrLength - 1) / 32))
                )
            );
        }
        taskIds = taskManager.submitTaskBatch(msg.sender, dataHash);
        emit RequestConsolidate(taskIds, _params);
    }

    /**
     * @dev Consolidate the token
     */
    function consolidate(
        string calldata _fromAddress,
        bytes32 _ticker,
        uint64 _chainId,
        uint256 _amount,
        bytes32 _salt,
        string calldata _txHash
    ) external onlyRole(ENTRYPOINT_ROLE) validateAsset(_ticker, _chainId) {
        consolidateRecords[_ticker][_chainId].push(
            ConsolidateTaskParam(_fromAddress, _ticker, _chainId, _amount, _salt)
        );
        emit Consolidate(_ticker, _chainId, _fromAddress, _amount, _txHash);
    }
}
