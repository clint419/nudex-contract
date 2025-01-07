// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {State} from "./ITaskManager.sol";

struct TaskOperation {
    uint64 taskId;
    State state;
    bytes extraData;
}

contract IEntryPoint {
    event SubmitterChosen(address indexed newSubmitter);
    event SubmitterRotationRequested(address indexed requester, address indexed currentSubmitter);

    error EmptyOperationsArray();
    error InvalidSigner(address sender);
    error IncorrectSubmitter(address sender, address submitter);
    error RotationWindowNotPassed(uint256 current, uint256 window);
    error InvalidAddress();
    error ExceedMaxOptCount();
    error NotEligibleForPending(uint64 taskId);
}
