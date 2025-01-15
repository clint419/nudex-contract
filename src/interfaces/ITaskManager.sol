// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

enum State {
    Created,
    Pending,
    Completed,
    Failed
}

struct Task {
    uint64 id;
    State state;
    address submitter;
    address handler;
    uint32 createdAt;
    uint32 updatedAt;
    bytes result;
}

interface ITaskManager {
    event TaskSubmitted(uint64 indexed taskId, address indexed submitter, address indexed handler);
    event TaskUpdated(
        uint64 indexed taskId,
        address indexed submitter,
        State indexed state,
        uint256 updateTime,
        bytes result
    );

    error EmptyTask();
    error InvalidTask(uint64 taskId);

    function getTask(uint64) external view returns (Task memory);

    function getLatestTask() external view returns (Task memory);

    function getUncompletedTasks() external view returns (Task[] memory);

    function getTaskState(uint64 _taskId) external view returns (State);

    function submitTask(address _submitter, bytes calldata _context) external returns (uint64);

    function updateTask(uint64 _taskId, State _state, bytes calldata _result) external;
}
