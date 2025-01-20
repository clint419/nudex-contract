// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {EntryPointUpgradeable, TaskOperation} from "../src/EntryPointUpgradeable.sol";

contract SignatureGenerator is Script {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    EntryPointUpgradeable entryPoint;

    function setUp() public {
        entryPoint = EntryPointUpgradeable(vm.envAddress("VOTING_MANAGER_ADDR"));
    }

    function run() public {
        uint256[] memory temp = new uint256[](3);
        temp[0] = 22;
        // generateOptSignature(temp);
    }

    // forge script --rpc-url localhost script/SignatureGenerator.sol --sig "run((address,uint8, uint64, bytes)[],uint256)"
    function run(uint64[] calldata _taskIds, uint256 _privKey) public pure returns (bytes memory) {
        bytes memory encodedData = abi.encode(_taskIds, entryPoint.tssNonce(), block.chainid);
        bytes32 digest = keccak256(encodedData).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privKey, digest);
        console.logBytes(abi.encodePacked(r, s, v));
        return abi.encodePacked(r, s, v);
    }

    function run2(bytes32 _digest, uint256 _privKey) public pure {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privKey, _digest);
        console.logBytes(abi.encodePacked(r, s, v));
    }

    // forge script script/SignatureGenerator.sol --sig "recover(bytes32,bytes)"
    function recover(bytes32 digest, bytes calldata signature) public pure returns (address) {
        return digest.recover(signature);
    }

    // forge script --rpc-url bscTestnet script/SignatureGenerator.sol --sig "generateOptSignature((uint64,uint8,bytes)[], uint256, uint256, uint256)" "[(0, 2, 0x)]" 0 56 1234
    function generateOptSignature(
        TaskOperation[] memory _operations,
        uint256 _nonce,
        uint256 _chainId,
        uint256 _privateKey
    ) public pure returns (bytes memory) {
        bytes memory encodedData = abi.encode(_operations, _nonce, _chainId);
        bytes32 digest = keccak256(encodedData).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
