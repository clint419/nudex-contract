// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {HandlerBase} from "./HandlerBase.sol";
import {IAssetHandler} from "../interfaces/IAssetHandler.sol";
import {IFundsHandler} from "../interfaces/IFundsHandler.sol";
import {INIP20} from "../interfaces/INIP20.sol";

contract FundsHandlerUpgradeable is IFundsHandler, HandlerBase {
    IAssetHandler public immutable assetHandler;

    mapping(bytes32 pauseType => bool isPaused) public pauseState;
    mapping(string userAddr => DepositInfo[]) public deposits;
    mapping(string userAddr => WithdrawalInfo[]) public withdrawals;

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
    function getDeposits(
        string calldata _depositAddress
    ) external view returns (DepositInfo[] memory) {
        require(bytes(_depositAddress).length > 0, InvalidAddress());
        return deposits[_depositAddress];
    }

    /**
     * @dev Get n-th deposit record of user.
     */
    function getDeposit(
        string calldata _depositAddress,
        uint256 _index
    ) external view returns (DepositInfo memory) {
        require(bytes(_depositAddress).length > 0, InvalidAddress());
        return deposits[_depositAddress][_index];
    }

    /**
     * @dev Get all withdraw records of user.
     */
    function getWithdrawals(
        string calldata _depositAddress
    ) external view returns (WithdrawalInfo[] memory) {
        return withdrawals[_depositAddress];
    }

    /**
     * @dev Get n-th withdraw record of user.
     */
    function getWithdrawal(
        string calldata _depositAddress,
        uint256 _index
    ) external view returns (WithdrawalInfo memory) {
        require(bytes(_depositAddress).length > 0, InvalidAddress());
        return withdrawals[_depositAddress][_index];
    }

    // TODO: role for adjusting Pause state
    function setPauseState(bytes32 _condition, bool _newState) external onlyRole(ENTRYPOINT_ROLE) {
        pauseState[_condition] = _newState;
        emit NewPauseState(_condition, _newState);
    }

    /**
     * @dev Submit deposit task.
     * @param _userAddress The EVM address of the user.
     * @param _depositAddress The deposit address assigned to the user.
     * @param _ticker The ticker of the asset.
     * @param _chainId The chain id of the asset.
     * @param _amount The amount to deposit.
     */
    // TODO: add contract address?
    function submitDepositTask(
        address _userAddress,
        string calldata _depositAddress,
        bytes32 _ticker,
        bytes32 _chainId,
        uint256 _amount
    ) external onlyRole(SUBMITTER_ROLE) returns (uint64) {
        require(!pauseState[_ticker] && !pauseState[bytes32(_chainId)], Paused());
        require(_amount >= assetHandler.getAssetDetails(_ticker).minDepositAmount, InvalidAmount());
        require(bytes(_depositAddress).length > 0, InvalidAddress());
        return
            taskManager.submitTask(
                msg.sender,
                abi.encodeWithSelector(
                    this.recordDeposit.selector,
                    _userAddress,
                    _depositAddress,
                    _ticker,
                    _chainId,
                    _amount
                )
            );
    }

    /**
     * @dev Record deposit info.
     */
    function recordDeposit(
        address _userAddress,
        string calldata _depositAddress,
        bytes32 _ticker,
        bytes32 _chainId,
        uint256 _amount
    ) external onlyRole(ENTRYPOINT_ROLE) returns (bytes memory) {
        deposits[_depositAddress].push(
            DepositInfo({
                depositAddress: _depositAddress,
                ticker: _ticker,
                chainId: _chainId,
                amount: _amount
            })
        );
        emit INIP20.NIP20TokenEvent_mintb(_userAddress, _ticker, _amount);
        emit DepositRecorded(_depositAddress, _ticker, _chainId, _amount);
        return abi.encodePacked(uint8(1), _depositAddress, _ticker, _chainId, _amount);
    }

    /**
     * @dev Submit withdraw task.
     * @param _userAddress The EVM address of the user.
     * @param _depositAddress The deposit address assigned to the user.
     * @param _ticker The ticker of the asset.
     * @param _chainId The chain id of the asset.
     * @param _amount The amount to withdraw.
     */
    function submitWithdrawTask(
        address _userAddress,
        string calldata _depositAddress,
        bytes32 _ticker,
        bytes32 _chainId,
        uint256 _amount
    ) external onlyRole(SUBMITTER_ROLE) returns (uint64) {
        require(!pauseState[_ticker] && !pauseState[bytes32(_chainId)], Paused());
        require(bytes(_depositAddress).length > 0, InvalidAddress());
        require(
            _amount >= assetHandler.getAssetDetails(_ticker).minWithdrawAmount,
            InvalidAmount()
        );
        emit INIP20.NIP20TokenEvent_burnb(_userAddress, _ticker, _amount);
        return
            taskManager.submitTask(
                msg.sender,
                abi.encodeWithSelector(
                    this.recordWithdrawal.selector,
                    _depositAddress,
                    _ticker,
                    _chainId,
                    _amount
                )
            );
    }

    /**
     * @dev Record withdraw info.
     */
    function recordWithdrawal(
        string calldata _depositAddress,
        bytes32 _ticker,
        bytes32 _chainId,
        uint256 _amount
    ) external onlyRole(ENTRYPOINT_ROLE) returns (bytes memory) {
        withdrawals[_depositAddress].push(
            WithdrawalInfo({
                depositAddress: _depositAddress,
                ticker: _ticker,
                chainId: _chainId,
                amount: _amount
            })
        );
        assetHandler.withdraw(_ticker, _chainId, _amount);
        emit WithdrawalRecorded(_depositAddress, _ticker, _chainId, _amount);
        return abi.encodePacked(uint8(1), _depositAddress, _ticker, _chainId, _amount);
    }
}
