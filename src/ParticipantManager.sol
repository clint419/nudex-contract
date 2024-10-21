// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IParticipantManager.sol";
import "./interfaces/INuvoLock.sol";

contract ParticipantManager is IParticipantManager, OwnableUpgradeable {
    INuvoLock public nuvoLock;
    uint256 public minLockAmount;
    uint256 public minLockPeriod;

    address[] public participants;
    mapping(address => bool) public isParticipant;

    function initialize(address _nuvoLock, uint256 _minLockAmount, uint256 _minLockPeriod, address _owner, address _initialParticipant) initializer public {
        __Ownable_init(_owner);
        nuvoLock = INuvoLock(_nuvoLock);
        minLockAmount = _minLockAmount;
        minLockPeriod = _minLockPeriod;
        
        participants.push(_initialParticipant);
        isParticipant[_initialParticipant] = true;
    }

    function addParticipant(address newParticipant) external onlyOwner {
        require(!isParticipant[newParticipant], "Already a participant");
        require(isEligible(newParticipant), "Participant not eligible");

        participants.push(newParticipant);
        isParticipant[newParticipant] = true;

        emit ParticipantAdded(newParticipant);
    }

    function removeParticipant(address participant) external onlyOwner {
        require(isParticipant[participant], "Not a participant");

        isParticipant[participant] = false;
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i] == participant) {
                participants[i] = participants[participants.length - 1];
                participants.pop();
                break;
            }
        }

        emit ParticipantRemoved(participant);
    }

    function isEligible(address participant) public view returns (bool) {
        (uint256 amount, uint256 unlockTime, , , , , ,) = nuvoLock.getLockInfo(participant);
        return amount >= minLockAmount && unlockTime >= block.timestamp + minLockPeriod;
    }

    function getParticipants() external view returns (address[] memory) {
        return participants;
    }
}
