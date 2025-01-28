// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IEntryPoint, TaskOperation} from "./interfaces/IEntryPoint.sol";
import {IParticipantHandler} from "./interfaces/IParticipantHandler.sol";
import {INuvoLock} from "./interfaces/INuvoLock.sol";
import {ITaskManager, State, Task} from "./interfaces/ITaskManager.sol";

/**
 * @dev Manage all onchain information.
 */
contract EntryPointUpgradeable is IEntryPoint, Initializable, ReentrancyGuardUpgradeable {
    uint256 public constant FORCE_ROTATION_WINDOW = 1 minutes;
    uint256 public constant MAX_OPT_COUNT = 256;

    IParticipantHandler public participantHandler;
    ITaskManager public taskManager;
    INuvoLock public nuvoLock;

    uint256 public lastSubmissionTime;
    uint256 public tssNonce;
    address public tssSigner;
    address public nextSubmitter;

    modifier onlyCurrentSubmitter() {
        require(msg.sender == nextSubmitter, IncorrectSubmitter(msg.sender, nextSubmitter));
        _;
        _rotateSubmitter();
    }

    /**
     * @dev Initializes the contract.
     * @param _tssSigner The address of tssSigner.
     * @param _participantHandler The address of ParticipantHandler contract address.
     * @param _taskManager The address of TaskManag contract address.
     * @param _nuvoLock The address of NuvoLock contract address.
     */
    function initialize(
        address _tssSigner,
        address _participantHandler,
        address _taskManager,
        address _nuvoLock
    ) public initializer {
        __ReentrancyGuard_init();

        participantHandler = IParticipantHandler(_participantHandler);
        taskManager = ITaskManager(_taskManager);
        nuvoLock = INuvoLock(_nuvoLock);

        require(_tssSigner != address(0), InvalidAddress());
        tssSigner = _tssSigner;
        lastSubmissionTime = block.timestamp;
        nextSubmitter = participantHandler.getRandomParticipant(nextSubmitter);
        emit SubmitterChosen(nextSubmitter);
    }

    /**
     * @dev Verify operation signature.
     * @param _operations The batch tasks to be executed.
     * @param _nonce The nonce of tssSigner.
     * @param _signature The signature for verification.
     */
    function verifyOperation(
        TaskOperation[] calldata _operations,
        uint256 _nonce,
        bytes calldata _signature
    ) external view returns (bool) {
        return _verifyOperation(_operations, _nonce, _signature);
    }

    /**
     * @dev Message hash helper function.
     * @param _operations The ids of batch task to be executed.
     * @param _nonce The nonce of tssSigner.
     */
    function operationHash(
        TaskOperation[] calldata _operations,
        uint256 _nonce
    ) external view returns (bytes32 hash, bytes32 messageHash) {
        hash = keccak256(abi.encode(_operations, _nonce, block.chainid));
        messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    /**
     * @dev Set new tssSigner address.
     * @param _newSigner The new tssSigner address.
     * @param _signature The signature for verification.
     */
    function setSignerAddress(
        address _newSigner,
        bytes calldata _signature
    ) external onlyCurrentSubmitter {
        require(_newSigner != address(0), InvalidAddress());
        require(
            _verifySignature(
                keccak256(abi.encodePacked(_newSigner, tssNonce++, block.chainid)),
                _signature
            ),
            InvalidSigner(msg.sender)
        );

        tssSigner = _newSigner;
        emit SetSigner(_newSigner);
    }

    /**
     * @dev Set dependency addresses.
     * @param _participantHandler The new participantHandler address.
     * @param _taskManager The new taskManager address.
     * @param _nuvoLock The new nuvoLock address.
     */
    function setDependency(
        address _participantHandler,
        address _taskManager,
        address _nuvoLock,
        bytes calldata _signature
    ) external onlyCurrentSubmitter {
        require(
            _verifySignature(
                keccak256(
                    abi.encodePacked(
                        _participantHandler,
                        _taskManager,
                        _nuvoLock,
                        tssNonce++,
                        block.chainid
                    )
                ),
                _signature
            ),
            InvalidSigner(msg.sender)
        );
        if (_participantHandler != address(0)) {
            participantHandler = IParticipantHandler(_participantHandler);
        }
        if (_taskManager != address(0)) {
            taskManager = ITaskManager(_taskManager);
        }
        if (_nuvoLock != address(0)) {
            nuvoLock = INuvoLock(_nuvoLock);
        }
    }

    /**
     * @dev Pick new random submitter if the current submitter is inactive for too long.
     * @param _signature The signature for verification.
     */
    function chooseNewSubmitter(
        uint256 _uncompletedTaskCount,
        bytes calldata _signature
    ) external nonReentrant {
        require(
            participantHandler.isParticipant(msg.sender),
            IParticipantHandler.NotParticipant(msg.sender)
        );
        require(
            block.timestamp >= lastSubmissionTime + FORCE_ROTATION_WINDOW,
            RotationWindowNotPassed(block.timestamp, lastSubmissionTime + FORCE_ROTATION_WINDOW)
        );
        require(
            _verifySignature(
                keccak256(abi.encodePacked(_uncompletedTaskCount, tssNonce++, block.chainid)),
                _signature
            ),
            InvalidSigner(msg.sender)
        );
        nuvoLock.accumulateDemeritPoints(nextSubmitter, _uncompletedTaskCount);
        emit SubmitterRotationRequested(msg.sender, nextSubmitter);
        _rotateSubmitter();
    }

    /**
     * @dev Entry point for all task handlers
     * @param _operations The batch tasks to be executed.
     * @param _signature The signature for verification.
     */
    // TODO: pass in rsv instead of signature?
    function verifyAndCall(
        TaskOperation[] calldata _operations,
        bytes calldata _signature
    ) external {
        // FIXME: testing only
        // ) external onlyCurrentSubmitter nonReentrant {
        // require(_verifyOperation(_operations, tssNonce++, _signature), InvalidSigner(msg.sender));
        bool success;
        bytes memory result;
        Task memory task;
        for (uint8 i; i < _operations.length; ) {
            task = taskManager.getTask(_operations[i].taskId);
            // execute task
            if (_operations[i].state == State.Completed) {
                result = bytes.concat(task.result, _operations[i].extraData);
                (success, result) = task.handler.call(result);
                if (success) {
                    // success
                    taskManager.updateTask(task.id, State.Completed, result);
                } else {
                    // fail
                    taskManager.updateTask(task.id, State.Failed, result);
                }
            }
            // pending task
            else if (_operations[i].state == State.Pending) {
                taskManager.updateTask(
                    _operations[i].taskId,
                    State.Pending,
                    bytes.concat(task.result, _operations[i].extraData)
                );
            }
            // fail task
            else if (_operations[i].state == State.Failed) {
                taskManager.updateTask(
                    _operations[i].taskId,
                    State.Failed,
                    _operations[i].extraData
                );
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Verify the validity of the operation.
     * @param _operations The ids of batch operation to be executed.
     * @param _nonce The nonce of tssSigner.
     * @param _signature The signature for verification.
     */
    function _verifyOperation(
        TaskOperation[] calldata _operations,
        uint256 _nonce,
        bytes calldata _signature
    ) internal view returns (bool) {
        require(_operations.length > 0, EmptyOperationsArray());
        require(_operations.length <= MAX_OPT_COUNT, ExceedMaxOptCount());
        return
            _verifySignature(keccak256(abi.encode(_operations, _nonce, block.chainid)), _signature);
    }

    /**
     * @dev Verify the hash message.
     * @param _hash The hashed message.
     * @param _signature The signature for verification.
     */
    function _verifySignature(
        bytes32 _hash,
        bytes calldata _signature
    ) internal view returns (bool) {
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", _hash)
        );
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(_signature);
        address recoverAddr = ecrecover(messageHash, v, r, s);
        return tssSigner == recoverAddr;
    }

    /**
     * @dev Pick a new random submiter from the participant list.
     */
    function _rotateSubmitter() internal {
        nuvoLock.accumulateBonusPoints(msg.sender, 1);
        lastSubmissionTime = block.timestamp;
        nextSubmitter = participantHandler.getRandomParticipant(nextSubmitter);
        emit SubmitterChosen(nextSubmitter);
    }

    /**
     * @dev Get rsv from signature.
     */
    function _splitSignature(
        bytes memory sig
    ) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        if (v < 27) {
            v += 27;
        }

        require(v == 27 || v == 28, "Invalid signature version");
    }
}
