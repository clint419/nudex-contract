// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {HandlerBase} from "./HandlerBase.sol";
import {IAssetHandler} from "../interfaces/IAssetHandler.sol";
import {IFundsHandler, DepositInfo, WithdrawalInfo} from "../interfaces/IFundsHandler.sol";
import {INIP20} from "../interfaces/INIP20.sol";
import {console} from "forge-std/console.sol";

contract FundsHandlerUpgradeable is IFundsHandler, HandlerBase {
    IAssetHandler public immutable assetHandler;

    mapping(bytes32 pauseType => bool isPaused) public pauseState;
    mapping(address userAddr => DepositInfo[]) public deposits;
    mapping(address userAddr => WithdrawalInfo[]) public withdrawals;

    constructor(address _assetHandler, address _taskManager) HandlerBase(_taskManager) {
        assetHandler = IAssetHandler(_assetHandler);
    }

    // _owner: EntryPoint contract
    function initialize(
        address _owner,
        address _entryPoint,
        address _submitter
    ) public initializer {
        __HandlerBase_init(_owner, _entryPoint, _submitter);
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

    // TODO: role for adjusting Pause state
    function setPauseState(bytes32 _condition, bool _newState) external onlyRole(ENTRYPOINT_ROLE) {
        pauseState[_condition] = _newState;
        emit NewPauseState(_condition, _newState);
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
    function submitDepositTask(DepositInfo[] calldata _params) external onlyRole(SUBMITTER_ROLE) {
        for (uint8 i; i < _params.length; i++) {
            require(
                !pauseState[_params[i].ticker] && !pauseState[bytes32(uint256(_params[i].chainId))],
                Paused()
            );
            require(
                _params[i].amount >=
                    assetHandler.getAssetDetails(_params[i].ticker).minDepositAmount,
                InvalidAmount()
            );
            require(bytes(_params[i].depositAddress).length > 0, InvalidAddress());
            taskManager.submitTask(
                msg.sender,
                abi.encodeWithSelector(this.recordDeposit.selector, _params[i])
            );
        }
    }

    /**
     * @dev Record deposit info.
     */
    function recordDeposit(
        DepositInfo calldata _param
    ) external onlyRole(ENTRYPOINT_ROLE) returns (bytes memory) {
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
     */
    function submitWithdrawTask(
        WithdrawalInfo[] calldata _params
    ) external onlyRole(SUBMITTER_ROLE) {
        for (uint8 i; i < _params.length; i++) {
            require(
                !pauseState[_params[i].ticker] && !pauseState[bytes32(uint256(_params[i].chainId))],
                Paused()
            );
            require(
                _params[i].amount >=
                    assetHandler.getAssetDetails(_params[i].ticker).minWithdrawAmount,
                InvalidAmount()
            );
            require(bytes(_params[i].toAddress).length > 0, InvalidAddress());
            emit INIP20.NIP20TokenEvent_burnb(
                _params[i].userAddress,
                _params[i].ticker,
                _params[i].amount
            );
            taskManager.submitTask(
                msg.sender,
                abi.encodeWithSelector(
                    this.recordWithdrawal.selector,
                    _params[i].userAddress,
                    _params[i].chainId,
                    _params[i].ticker,
                    _params[i].toAddress,
                    _params[i].amount,
                    uint256(256)
                )
            );
        }
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
        string calldata _txHash
    ) external onlyRole(ENTRYPOINT_ROLE) returns (bytes memory) {
        withdrawals[_userAddress].push(
            WithdrawalInfo(_userAddress, _chainId, _ticker, _toAddress, _amount)
        );
        assetHandler.withdraw(_ticker, _chainId, _amount);
        emit WithdrawalRecorded(_userAddress, _ticker, _chainId, _toAddress, _amount, _txHash);
        return abi.encode(uint8(1), _userAddress, _chainId, _ticker, _toAddress, _amount, _txHash);
    }
}
