// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

enum State {
    Created,
    Pending,
    Completed,
    Failed
}

struct Task {
    State state;
    address submitter;
    address handler;
    uint32 createdAt;
    uint32 updatedAt;
    bytes32 dataHash;
}

interface ITaskManager {
    event TaskSubmitted(
        uint64 indexed taskId,
        address indexed submitter,
        address indexed handler,
        bytes32 dataHash
    );
    event TaskSubmittedBatch(
        uint64[] indexed taskIds,
        address indexed submitter,
        address indexed handler,
        bytes32[] dataHashs
    );
    event TaskUpdated(
        uint64 indexed taskId,
        address indexed submitter,
        State indexed state,
        uint256 updateTime
    );

    error EmptyTask();
    error InvalidTask(uint64 taskId);

    function getTask(uint64) external view returns (Task memory);

    function getLatestTask() external view returns (Task memory);

    function getUncompletedTasks() external view returns (Task[] memory);

    function getTaskState(uint64 _taskId) external view returns (State);

    function submitTask(address _submitter, bytes32 _context) external returns (uint64);

    function submitTaskBatch(
        address _submitter,
        bytes32[] calldata _context
    ) external returns (uint64[] memory);

    function updateTask(uint64 _taskId, State _state) external;
}
