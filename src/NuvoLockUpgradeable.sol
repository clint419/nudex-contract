// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INuvoLock} from "./interfaces/INuvoLock.sol";

contract NuvoLockUpgradeable is INuvoLock, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    uint256 private initTimestamp;

    IERC20 public nuvoToken;
    address public rewardSource;
    uint32 public lastPeriodNumber; // Tracks the last reward period
    uint256 public minLockAmount;
    uint256 public minLockPeriod;
    uint256 public totalBonusPoints;
    uint256 public totalLocked;

    mapping(address => LockInfo) public locks;
    mapping(uint256 => uint256) public rewardPerPeriod; // Maps period number to its reward amount
    address[] public users;
    mapping(address => uint256) public userIndex;

    modifier onlyUser() {
        require(locks[msg.sender].amount > 0, NotAUser(msg.sender));
        _;
    }

    function initialize(
        address _nuvoToken,
        address _rewardSource,
        address _owner,
        uint256 _minLockAmount,
        uint256 _minLockPeriod
    ) public initializer {
        __Ownable_init(_owner);

        nuvoToken = IERC20(_nuvoToken);
        rewardSource = _rewardSource;
        initTimestamp = block.timestamp;
        minLockPeriod = _minLockPeriod;
        minLockAmount = _minLockAmount;
        lastPeriodNumber = getCurrentPeriod();
    }

    function getCurrentPeriod() public view returns (uint32) {
        return uint32((block.timestamp - initTimestamp) / 1 weeks);
    }

    function lockedBalanceOf(address _userAddr) external view returns (uint256) {
        return locks[_userAddr].amount;
    }

    function lockedTime(address _userAddr) external view returns (uint256) {
        return block.timestamp - locks[_userAddr].startTime;
    }

    function setMinLockInfo(uint256 _minLockAmount, uint32 _minLockPeriod) external onlyOwner {
        minLockAmount = _minLockAmount;
        minLockPeriod = _minLockPeriod;
        emit MinLockInfo(minLockAmount, minLockPeriod);
    }

    function setRewardPerPeriod(uint256 _newRewardPerPeriod) external onlyOwner {
        // Accumulate rewards for all previous periods before updating the reward per period
        accumulateRewards();

        // Update rewardPerPeriod for the current period
        rewardPerPeriod[lastPeriodNumber] = _newRewardPerPeriod;

        emit RewardPerPeriodUpdated(_newRewardPerPeriod, lastPeriodNumber);
    }

    function lock(uint256 _amount, uint32 _period) external {
        require(_amount >= minLockAmount, AmountBelowMin(_amount));
        require(_period >= minLockPeriod, TimePeriodBelowMin(_period));
        require(locks[msg.sender].amount == 0, AlreadyLocked(msg.sender));

        uint32 unlockTime = uint32(block.timestamp + _period);
        locks[msg.sender] = LockInfo({
            amount: _amount,
            unlockTime: unlockTime,
            originalLockTime: _period,
            startTime: uint32(block.timestamp),
            bonusPoints: 0,
            accumulatedRewards: 0,
            lastClaimedPeriod: lastPeriodNumber,
            demeritPoints: 0
        });

        // Transfer NUVO tokens from the user to the contract
        nuvoToken.safeTransferFrom(msg.sender, address(this), _amount);
        totalLocked += _amount;
        // record userAddr
        userIndex[msg.sender] = users.length;
        users.push(msg.sender);

        emit Locked(msg.sender, _amount, unlockTime);
    }

    function unlock() external onlyUser {
        LockInfo storage lockInfo = locks[msg.sender];
        require(
            block.timestamp >= lockInfo.unlockTime,
            UnlockedTimeNotReached(block.timestamp, lockInfo.unlockTime)
        );
        // Accumulate rewards for all unaccounted periods before unlocking
        accumulateRewards();

        uint256 amount = lockInfo.amount;
        lockInfo.amount = 0;
        totalLocked -= amount;
        // remove userAddr
        users[userIndex[msg.sender]] = users[users.length - 1];
        users.pop();
        nuvoToken.safeTransfer(msg.sender, amount);

        emit Unlocked(msg.sender, amount);
    }

    function accumulateBonusPoints(address _userAddr) external onlyOwner {
        require(locks[_userAddr].amount > 0, NotAUser(_userAddr));

        // Check if the reward period has ended and accumulate rewards if necessary
        if (getCurrentPeriod() > lastPeriodNumber) {
            accumulateRewards();
        }

        // Accumulate points
        locks[_userAddr].bonusPoints++;
        totalBonusPoints++;
    }

    function accumulateDemeritPoints(address _userAddr) external onlyOwner {
        require(locks[_userAddr].amount > 0, NotAUser(_userAddr));

        // Check if the reward period has ended and accumulate rewards if necessary
        if (getCurrentPeriod() > lastPeriodNumber) {
            accumulateRewards();
        }

        // Accumulate points
        locks[_userAddr].demeritPoints++;
    }

    // calculate reward of every user for the last period
    function accumulateRewards() public {
        uint32 currentPeriodNumber = getCurrentPeriod();

        if (currentPeriodNumber > lastPeriodNumber) {
            if (totalBonusPoints > 0 && rewardPerPeriod[lastPeriodNumber] > 0) {
                address userAddr;
                LockInfo storage lockInfo;
                for (uint256 i = 0; i < users.length; i++) {
                    userAddr = users[i];
                    lockInfo = locks[userAddr];
                    uint256 userBonusPoints = (lockInfo.bonusPoints > lockInfo.demeritPoints)
                        ? lockInfo.bonusPoints - lockInfo.demeritPoints
                        : 0;
                    if (lockInfo.demeritPoints > 0) {
                        lockInfo.demeritPoints--;
                    }

                    if (userBonusPoints > 0) {
                        uint256 userReward = (rewardPerPeriod[lastPeriodNumber] * userBonusPoints) /
                            totalBonusPoints;
                        lockInfo.accumulatedRewards += userReward;

                        emit RewardsAccumulated(userAddr, userReward);
                    }

                    // Reset bonus points for the user during the same loop
                    lockInfo.bonusPoints = 0;
                }

                // Reset the total bonus points for the next period
                totalBonusPoints = 0;
                // Update the last period
                lastPeriodNumber = currentPeriodNumber;
            }
        }
    }

    function claimRewards() external onlyUser {
        LockInfo storage lockInfo = locks[msg.sender];
        uint256 rewards = lockInfo.accumulatedRewards;
        require(rewards > 0, NothingToClaim());

        lockInfo.accumulatedRewards = 0;
        nuvoToken.safeTransferFrom(rewardSource, msg.sender, rewards);

        emit RewardsClaimed(msg.sender, rewards);
    }
}
