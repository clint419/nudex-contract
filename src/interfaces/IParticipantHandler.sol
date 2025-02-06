// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IParticipantHandler {
    event ParticipantAdded(address indexed participant);
    event ParticipantRemoved(address indexed participant);
    event ParticipantsReset(address[] indexed participants);
    event RequestAddParticipant(uint64 taskId, address indexed participants);
    event RequestRemoveParticipant(uint64 taskId, address indexed participants);
    event RequestResetParticipants(uint64 taskId, address[] indexed participants);

    error AlreadyParticipant(address);
    error NotEligible(address);
    error NotParticipant(address);
    error NotEnoughParticipant();

    function isParticipant(address) external view returns (bool);

    function addParticipant(address newParticipant, bytes32 _salt) external;

    function removeParticipant(address participant, bytes32 _salt) external;

    function getParticipants() external view returns (address[] memory);

    function getRandomParticipant(address _salt) external view returns (address randParticipant);
}
