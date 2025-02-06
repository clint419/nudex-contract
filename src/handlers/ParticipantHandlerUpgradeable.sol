// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {HandlerBase} from "./HandlerBase.sol";
import {IParticipantHandler} from "../interfaces/IParticipantHandler.sol";
import {INuvoLock} from "../interfaces/INuvoLock.sol";

contract ParticipantHandlerUpgradeable is IParticipantHandler, HandlerBase {
    INuvoLock public immutable nuvoLock;

    address[] public participants;
    mapping(address => bool) public isParticipant;

    constructor(address _nuvoLock, address _taskManager) HandlerBase(_taskManager) {
        nuvoLock = INuvoLock(_nuvoLock);
    }

    // _owner: EntryPoint
    function initialize(
        address _owner,
        address _entryPoint,
        address _submitter,
        address[] calldata _initialParticipants
    ) public initializer {
        require(_initialParticipants.length > 2, NotEnoughParticipant());
        participants = _initialParticipants;
        for (uint256 i; i < _initialParticipants.length; ++i) {
            isParticipant[_initialParticipants[i]] = true;
        }
        __HandlerBase_init(_owner, _entryPoint, _submitter);
    }

    /**
     * @dev Get all participant.
     */
    function getParticipants() external view returns (address[] memory) {
        return participants;
    }

    /**
     * @dev Pick one random participant.
     * @param _salt Salt for randomness.
     */
    function getRandomParticipant(address _salt) external view returns (address randParticipant) {
        uint256 randomIndex = uint256(
            keccak256(
                abi.encodePacked(
                    block.prevrandao, // instead of difficulty in PoS
                    block.timestamp,
                    blockhash(block.number),
                    _salt
                )
            )
        ) % participants.length;
        randParticipant = participants[randomIndex];
    }

    /**
     * @dev Submit task to add new participant.
     * @param _newParticipant The new participant to be added.
     * @param _salt Salt for randomness.
     */
    function submitAddParticipantTask(
        address _newParticipant,
        bytes32 _salt
    ) external onlyRole(SUBMITTER_ROLE) returns (uint64 taskId) {
        require(!isParticipant[_newParticipant], AlreadyParticipant(_newParticipant));
        require(nuvoLock.lockedBalanceOf(_newParticipant) > 0, NotEligible(_newParticipant));
        taskId = taskManager.submitTask(
            msg.sender,
            keccak256(abi.encodeWithSelector(this.addParticipant.selector, _newParticipant, _salt))
        );
        emit RequestAddParticipant(taskId, _newParticipant);
    }

    /**
     * @dev Add new participant.
     * @param _newParticipant The new participant to be added.
     */
    function addParticipant(address _newParticipant, bytes32) external onlyRole(ENTRYPOINT_ROLE) {
        require(!isParticipant[_newParticipant], AlreadyParticipant(_newParticipant));
        require(nuvoLock.lockedBalanceOf(_newParticipant) > 0, NotEligible(_newParticipant));
        isParticipant[_newParticipant] = true;
        participants.push(_newParticipant);

        emit ParticipantAdded(_newParticipant);
    }

    /**
     * @dev Submit task to remove participant.
     * @param _participant The participant to be removed.
     * @param _salt Salt for randomness.
     */
    function submitRemoveParticipantTask(
        address _participant,
        bytes32 _salt
    ) external onlyRole(SUBMITTER_ROLE) returns (uint64 taskId) {
        require(participants.length > 3, NotEnoughParticipant());
        require(isParticipant[_participant], NotParticipant(_participant));
        taskId = taskManager.submitTask(
            msg.sender,
            keccak256(abi.encodeWithSelector(this.removeParticipant.selector, _participant, _salt))
        );
    }

    /**
     * @dev Remove participant.
     * @param _participant The participant to be removed.
     */
    function removeParticipant(address _participant, bytes32) external onlyRole(ENTRYPOINT_ROLE) {
        require(participants.length > 3, NotEnoughParticipant());
        require(isParticipant[_participant], NotParticipant(_participant));
        isParticipant[_participant] = false;
        for (uint8 i; i < participants.length; i++) {
            if (participants[i] == _participant) {
                participants[i] = participants[participants.length - 1];
                participants.pop();
                break;
            }
        }

        emit ParticipantRemoved(_participant);
    }

    /**
     * @dev Submit task to reset the whole participants.
     * @param _newParticipants The new participant list.
     * @param _salt Salt for randomness.
     */
    function submitResetParticipantsTask(
        address[] calldata _newParticipants,
        bytes32 _salt
    ) external onlyRole(SUBMITTER_ROLE) returns (uint64 taskId) {
        require(_newParticipants.length > 2, NotEnoughParticipant());
        taskId = taskManager.submitTask(
            msg.sender,
            keccak256(
                abi.encodeWithSelector(this.resetParticipants.selector, _newParticipants, _salt)
            )
        );
    }

    /**
     * @dev Reset the whole participants.
     * @param _newParticipants The new participant list.
     */
    function resetParticipants(
        address[] calldata _newParticipants,
        bytes32
    ) external onlyRole(ENTRYPOINT_ROLE) {
        // remove old participants
        for (uint8 i; i < participants.length; i++) {
            isParticipant[participants[i]] = false;
        }
        // add new participants
        for (uint8 i; i < _newParticipants.length; ++i) {
            require(
                nuvoLock.lockedBalanceOf(_newParticipants[i]) > 0,
                NotEligible(_newParticipants[i])
            );
            isParticipant[_newParticipants[i]] = true;
        }
        participants = _newParticipants;

        emit ParticipantsReset(_newParticipants);
    }
}
