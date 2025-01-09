pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {NuvoLockUpgradeable} from "../src/NuvoLockUpgradeable.sol";
import {ParticipantHandlerUpgradeable} from "../src/handlers/ParticipantHandlerUpgradeable.sol";
import {TaskManagerUpgradeable} from "../src/TaskManagerUpgradeable.sol";
import {EntryPointUpgradeable} from "../src/EntryPointUpgradeable.sol";

import {IEntryPoint, TaskOperation} from "../src/interfaces/IEntryPoint.sol";
import {State} from "../src/interfaces/ITaskManager.sol";
import {UintToString} from "../src/libs/UintToString.sol";

import {MockNuvoToken} from "../src/mocks/MockNuvoToken.sol";

contract BaseTest is Test {
    using MessageHashUtils for bytes32;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant ENTRYPOINT_ROLE = keccak256("ENTRYPOINT_ROLE");
    uint256 public constant MIN_LOCK_AMOUNT = 1 ether;
    uint32 public constant MIN_LOCK_PERIOD = 1 weeks;

    MockNuvoToken public nuvoToken;

    NuvoLockUpgradeable public nuvoLock;
    ParticipantHandlerUpgradeable public participantHandler;
    TaskManagerUpgradeable public taskManager;
    EntryPointUpgradeable public entryPoint;

    address public vmProxy;
    address public daoContract;
    address public thisAddr;
    address public msgSender;
    address public tssSigner;
    uint256 public tssKey;

    TaskOperation[] public taskOpts;
    address[] public handlers;
    bytes public signature;

    function setUp() public virtual {
        msgSender = makeAddr("msgSender");
        (tssSigner, tssKey) = makeAddrAndKey("tss");
        daoContract = makeAddr("dao");
        thisAddr = address(this);

        // deploy mock nuvoToken
        nuvoToken = new MockNuvoToken();
        nuvoToken.mint(msgSender, 100 ether);

        // deploy entryPoint proxy
        vmProxy = _deployProxy(address(new EntryPointUpgradeable()), daoContract);
        entryPoint = EntryPointUpgradeable(vmProxy);

        // deploy NuvoLockUpgradeable
        address nuvoLockProxy = _deployProxy(address(new NuvoLockUpgradeable()), daoContract);
        nuvoLock = NuvoLockUpgradeable(nuvoLockProxy);
        nuvoLock.initialize(
            address(nuvoToken),
            msgSender,
            vmProxy,
            MIN_LOCK_AMOUNT,
            MIN_LOCK_PERIOD
        );
        assertEq(nuvoLock.owner(), vmProxy);

        // deploy taskManager
        address tmProxy = _deployProxy(address(new TaskManagerUpgradeable()), daoContract);
        taskManager = TaskManagerUpgradeable(tmProxy);

        // deploy ParticipantHandlerUpgradeable
        address participantHandlerProxy = _deployProxy(
            address(new ParticipantHandlerUpgradeable(nuvoLockProxy, tmProxy)),
            daoContract
        );
        participantHandler = ParticipantHandlerUpgradeable(participantHandlerProxy);
        address[] memory participants = new address[](3);
        participants[0] = msgSender;
        participants[1] = msgSender;
        participants[2] = msgSender;
        participantHandler.initialize(daoContract, vmProxy, msgSender, participants);
        assertTrue(participantHandler.hasRole(ENTRYPOINT_ROLE, vmProxy));

        // setups
        vm.startPrank(msgSender);
        nuvoToken.approve(nuvoLockProxy, MIN_LOCK_AMOUNT);
        nuvoLock.lock(MIN_LOCK_AMOUNT, MIN_LOCK_PERIOD);
        vm.stopPrank();

        // initialize entryPoint link to all contracts
        entryPoint.initialize(
            tssSigner, // tssSigner
            address(participantHandler), // participantHandler
            address(taskManager), // taskManager
            address(nuvoLock) // nuvoLock
        );

        // misc
        taskOpts.push(TaskOperation(0, State.Completed, ""));
    }

    function _deployProxy(address _logic, address _admin) internal returns (address) {
        return address(new TransparentUpgradeableProxy(_logic, _admin, ""));
    }

    // generate signature for operations
    function _generateOptSignature(
        TaskOperation[] memory _operations,
        uint256 _privateKey
    ) internal view returns (bytes memory) {
        bytes memory encodedData = abi.encode(_operations, entryPoint.tssNonce(), block.chainid);
        bytes32 digest = keccak256(encodedData).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // generate signature for encoded data
    function _generateDataSignature(
        bytes memory _encodedData,
        uint256 _privateKey
    ) internal pure returns (bytes memory) {
        bytes32 digest = keccak256(_encodedData).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
