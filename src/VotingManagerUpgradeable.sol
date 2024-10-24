// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IAccountManager} from "./interfaces/IAccountManager.sol";
import {IAssetManager} from "./interfaces/IAssetManager.sol";
import {IDepositManager} from "./interfaces/IDepositManager.sol";
import {IParticipantManager} from "./interfaces/IParticipantManager.sol";
import {INuDexOperations} from "./interfaces/INuDexOperations.sol";
import {INuvoLock} from "./interfaces/INuvoLock.sol";
import {console} from "forge-std/console.sol";

contract VotingManagerUpgradeable is Initializable, ReentrancyGuardUpgradeable {
    IAccountManager public accountManager;
    IAssetManager public assetManager;
    IDepositManager public depositManager;
    IParticipantManager public participantManager;
    INuDexOperations public nuDexOperations;
    INuvoLock public nuvoLock;

    uint256 public lastSubmissionTime;
    uint256 public constant forcedRotationWindow = 1 minutes;
    uint256 public constant taskCompletionThreshold = 1 hours;

    address public nextSubmitter;

    event SubmitterChosen(address indexed newSubmitter);
    event RewardPerPeriodVoted(uint256 newRewardPerPeriod);
    event ParticipantAdded(address indexed newParticipant);
    event ParticipantRemoved(address indexed participant);
    event SubmitterRotationRequested(address indexed requester, address indexed currentSubmitter);

    error InvalidSigner();
    error IncorrectSubmitter();
    error RotationWindowNotPassed();
    error TaskAlreadyCompleted();

    modifier onlyParticipant() {
        require(participantManager.isParticipant(msg.sender), IParticipantManager.NotParticipant());
        _;
    }

    modifier onlyCurrentSubmitter() {
        require(msg.sender == nextSubmitter, IncorrectSubmitter());
        _;
    }

    function initialize(
        address _accountManager,
        address _assetManager,
        address _depositManager,
        address _participantManager,
        address _nuDexOperations,
        address _nuvoLock
    ) public initializer {
        __ReentrancyGuard_init();
        accountManager = IAccountManager(_accountManager);
        assetManager = IAssetManager(_assetManager);
        depositManager = IDepositManager(_depositManager);
        participantManager = IParticipantManager(_participantManager);
        nuDexOperations = INuDexOperations(_nuDexOperations);
        nuvoLock = INuvoLock(_nuvoLock);
        lastSubmissionTime = block.timestamp;
        nextSubmitter = participantManager.getRandomParticipant(nextSubmitter);
    }

    function addParticipant(
        address newParticipant,
        bytes memory signature
    ) external onlyCurrentSubmitter nonReentrant {
        require(verifySignature(abi.encodePacked(newParticipant), signature), InvalidSigner());
        participantManager.addParticipant(newParticipant);
        rotateSubmitter();

        emit ParticipantAdded(newParticipant);
    }

    function removeParticipant(
        address participant,
        bytes memory signature
    ) external onlyCurrentSubmitter nonReentrant {
        require(verifySignature(abi.encodePacked(participant), signature), InvalidSigner());

        participantManager.removeParticipant(participant);
        rotateSubmitter();

        emit ParticipantRemoved(participant);
    }

    function chooseNewSubmitter() external onlyParticipant nonReentrant {
        require(
            block.timestamp >= lastSubmissionTime + forcedRotationWindow,
            RotationWindowNotPassed()
        );

        // Check for uncompleted tasks and apply demerit points if needed
        INuDexOperations.Task[] memory uncompletedTasks = nuDexOperations.getUncompletedTasks();
        for (uint256 i = 0; i < uncompletedTasks.length; i++) {
            if (block.timestamp > uncompletedTasks[i].createdAt + taskCompletionThreshold) {
                //uncompleted tasks
                nuvoLock.accumulateDemeritPoints(nextSubmitter);
            }
        }
        emit SubmitterRotationRequested(msg.sender, nextSubmitter);
        rotateSubmitter();
    }

    function registerAccount(
        address _user,
        uint _account,
        IAccountManager.Chain _chain,
        uint _index,
        address _address,
        bytes memory _signature
    ) external onlyCurrentSubmitter nonReentrant {
        bytes memory encodedParams = abi.encodePacked(_user, _account, _chain, _index, _address);
        require(verifySignature(encodedParams, _signature), InvalidSigner());
        accountManager.registerNewAddress(_user, _account, _chain, _index, _address);
        rotateSubmitter();
    }

    function submitDepositInfo(
        address targetAddress,
        uint256 amount,
        uint256 chainId,
        bytes memory txInfo,
        bytes memory extraInfo,
        bytes memory signature
    ) external onlyCurrentSubmitter nonReentrant {
        bytes memory encodedParams = abi.encodePacked(
            targetAddress,
            amount,
            chainId,
            txInfo,
            extraInfo
        );
        require(verifySignature(encodedParams, signature), InvalidSigner());
        depositManager.recordDeposit(targetAddress, amount, chainId, txInfo, extraInfo);
        rotateSubmitter();
    }

    function setRewardPerPeriod(
        uint256 newRewardPerPeriod,
        bytes memory signature
    ) external onlyCurrentSubmitter nonReentrant {
        bytes memory encodedParams = abi.encodePacked(newRewardPerPeriod);
        require(verifySignature(encodedParams, signature), InvalidSigner());

        nuvoLock.setRewardPerPeriod(newRewardPerPeriod);
        emit RewardPerPeriodVoted(newRewardPerPeriod);
        rotateSubmitter();
    }

    function listAsset(
        string memory name,
        string memory nuDexName,
        IAssetManager.AssetType assetType,
        address contractAddress,
        uint256 chainId,
        bytes memory signature
    ) external onlyCurrentSubmitter nonReentrant {
        bytes memory encodedParams = abi.encodePacked(
            name,
            nuDexName,
            assetType,
            contractAddress,
            chainId
        );
        require(verifySignature(encodedParams, signature), InvalidSigner());
        assetManager.listAsset(name, nuDexName, assetType, contractAddress, chainId);

        rotateSubmitter();
    }

    function delistAsset(
        IAssetManager.AssetType assetType,
        address contractAddress,
        uint256 chainId,
        bytes memory signature
    ) external onlyCurrentSubmitter nonReentrant {
        bytes memory encodedParams = abi.encodePacked(assetType, contractAddress, chainId);
        require(verifySignature(encodedParams, signature), InvalidSigner());
        assetManager.delistAsset(assetType, contractAddress, chainId);

        rotateSubmitter();
    }

    function submitTaskReceipt(
        uint256 taskId,
        bytes memory result,
        bytes memory signature
    ) external onlyCurrentSubmitter nonReentrant {
        require(!nuDexOperations.isTaskCompleted(taskId), TaskAlreadyCompleted());
        bytes memory encodedParams = abi.encodePacked(taskId, result);
        require(verifySignature(encodedParams, signature), InvalidSigner());
        nuDexOperations.markTaskCompleted(taskId, result);
        rotateSubmitter();
    }

    function rotateSubmitter() internal {
        nuvoLock.accumulateBonusPoints(msg.sender);
        lastSubmissionTime = block.timestamp;
        nextSubmitter = participantManager.getRandomParticipant(nextSubmitter);
        emit SubmitterChosen(nextSubmitter);
    }

    function verifySignature(
        bytes memory encodedParams,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 hash = keccak256(
            abi.encodePacked(uint256ToString(encodedParams.length), encodedParams)
        );
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        address signer = ecrecover(messageHash, v, r, s);
        return participantManager.isParticipant(signer);
    }

    function splitSignature(
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

    function uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
