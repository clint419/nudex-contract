// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ITaskManager} from "../interfaces/ITaskManager.sol";

abstract contract HandlerBase is AccessControlUpgradeable {
    // Roles
    bytes32 public constant ENTRYPOINT_ROLE = keccak256("ENTRYPOINT_ROLE");
    bytes32 public constant SUBMITTER_ROLE = keccak256("SUBMITTER_ROLE");

    ITaskManager public immutable taskManager;

    constructor(address _taskManager) {
        taskManager = ITaskManager(_taskManager);
    }

    /**
     * @dev Initialize the contract.
     * @param _owner The owner of the contract.
     * @param _entryPoint The address of EntryPoint contract.
     * @param _submitter Whitelisted submitter address.
     */
    function __HandlerBase_init(
        address _owner,
        address _entryPoint,
        address _submitter
    ) internal onlyInitializing {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(ENTRYPOINT_ROLE, _entryPoint);
        _grantRole(SUBMITTER_ROLE, _submitter);
    }
}
