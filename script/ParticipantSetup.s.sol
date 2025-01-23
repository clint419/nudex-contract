// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MockNuvoToken} from "../src/mocks/MockNuvoToken.sol";
import {NuvoLockUpgradeable} from "../src/NuvoLockUpgradeable.sol";

// this contract is only used for contract testing
contract ParticipantSetup is Script {
    bytes32 constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    MockNuvoToken nuvoToken;
    NuvoLockUpgradeable nuvoLock;

    function setUp() public {
        nuvoToken = MockNuvoToken(vm.envAddress("NUVO_TOKEN_ADDR"));
        nuvoLock = NuvoLockUpgradeable(vm.envAddress("NUVO_LOCK_ADDR"));
        console.log("nuvoToken: ", address(nuvoToken));
        console.log("nuvoLock: ", address(nuvoLock));
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        uint256 privKey1 = vm.envUint("PARTICIPANT_KEY_1");
        address participant1 = vm.createWallet(privKey1).addr;
        nuvoToken.mint(participant1, 1 ether);
        _lockWithPermit(privKey1, participant1, 1 ether, 1 days);

        uint256 privKey2 = vm.envUint("PARTICIPANT_KEY_2");
        address participant2 = vm.createWallet(privKey2).addr;
        nuvoToken.mint(participant2, 1 ether);
        _lockWithPermit(privKey2, participant2, 1 ether, 1 days);

        uint256 privKey3 = vm.envUint("PARTICIPANT_KEY_3");
        address participant3 = vm.createWallet(privKey3).addr;
        nuvoToken.mint(participant3, 1 ether);
        _lockWithPermit(privKey3, participant3, 1 ether, 1 days);

        vm.stopBroadcast();
    }

    function _lockWithPermit(
        uint256 _privateKey,
        address _owner,
        uint256 _value,
        uint32 _period
    ) internal returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                _owner,
                address(nuvoLock),
                _value,
                nuvoToken.nonces(_owner),
                type(uint256).max
            )
        );
        bytes32 domainSeparator = nuvoToken.DOMAIN_SEPARATOR();
        structHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(_privateKey, structHash);
        nuvoLock.lockWithpermit(_owner, _value, _period, v, r, s);
    }
}
