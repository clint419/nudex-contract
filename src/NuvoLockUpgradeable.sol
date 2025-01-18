// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {INuvoLock} from "./interfaces/INuvoLock.sol";

contract NuvoLockUpgradeable is INuvoLock, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant ENTRYPOINT_ROLE = keccak256("ENTRYPOINT_ROLE");
    IERC20 public immutable nuvoToken;

    uint256 private initTimestamp;

    address public rewardSource;
    uint32 public lastPeriodNumber; // Tracks the last reward period
    uint256 public minLockAmount;
    uint256 public minLockPeriod;
    uint256 public totalBonusPoints;
    uint256 public totalLocked;

    address[] public users;
    mapping(address => LockInfo) public locks;
    mapping(uint256 => uint256) public rewardPerPeriod; // Maps period number to its reward amount
    mapping(address => uint256) public userIndex;

    modifier onlyUser() {
        require(locks[msg.sender].amount > 0, NotAUser(msg.sender));
        _;
    }

    constructor(address _nuvoToken) {
        nuvoToken = IERC20(_nuvoToken);
    }

    function initialize(
        address _rewardSource,
        address _dao,
        address _entryPoint,
        uint256 _minLockAmount,
        uint256 _minLockPeriod
    ) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _dao);
        _grantRole(ENTRYPOINT_ROLE, _entryPoint);

        rewardSource = _rewardSource;
        initTimestamp = block.timestamp;
        minLockAmount = _minLockAmount;
        minLockPeriod = _minLockPeriod;
        lastPeriodNumber = getCurrentPeriod();
    }

    /**
     * @dev Get current time period index.
     */
    function getCurrentPeriod() public view returns (uint32) {
        return uint32((block.timestamp - initTimestamp) / 1 weeks);
    }

    function lockedBalanceOf(address _userAddr) external view returns (uint256) {
        return locks[_userAddr].amount;
    }

    function lockedTime(address _userAddr) external view returns (uint256) {
        return block.timestamp - locks[_userAddr].startTime;
    }

    /**
     * @dev Set minimum lock threshold.
     * @param _minLockAmount New min lock amount.
     * @param _minLockPeriod New min lock period.
     */
    function setMinLockInfo(
        uint256 _minLockAmount,
        uint32 _minLockPeriod
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minLockAmount = _minLockAmount;
        minLockPeriod = _minLockPeriod;
        emit MinLockInfo(minLockAmount, minLockPeriod);
    }

    /**
     * @dev Set new reward per period.
     * @param _newRewardPerPeriod New reward per period.
     */
    function setRewardPerPeriod(uint256 _newRewardPerPeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Accumulate rewards for all previous periods before updating the reward per period
        accumulateRewards();

        // Update rewardPerPeriod for the current period
        rewardPerPeriod[lastPeriodNumber] = _newRewardPerPeriod;

        emit RewardPerPeriodUpdated(_newRewardPerPeriod, lastPeriodNumber);
    }

    /**
     * @dev Lock NuvoToken for msg.sender.
     * @param _amount The lock token amount.
     * @param _period The lock period.
     */
    function lock(uint256 _amount, uint32 _period) external {
        _lock(msg.sender, _amount, _period);
    }

    /**
     * @dev Lock NuvoToken using ERC20Permit for approval.
     * @param _owner The address to lock for.
     * @param _amount The amount of tokens to lock.
     * @param _period The lock period.
     * @param _v The recovery byte of the signature.
     * @param _r Half of the ECDSA signature pair.
     * @param _s Half of the ECDSA signature pair.
     */
    function lockWithpermit(
        address _owner,
        uint256 _amount,
        uint32 _period,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        IERC20Permit(address(nuvoToken)).permit(
            _owner,
            address(this),
            _amount,
            type(uint256).max,
            _v,
            _r,
            _s
        );
        _lock(_owner, _amount, _period);
    }

    function _lock(address _owner, uint256 _amount, uint32 _period) internal {
        require(_amount >= minLockAmount, AmountBelowMin(_amount));
        require(_period >= minLockPeriod, TimePeriodBelowMin(_period));
        // TODO: can only lock once?
        require(locks[_owner].amount == 0, AlreadyLocked(_owner));

        uint32 unlockTime = uint32(block.timestamp + _period);
        locks[_owner] = LockInfo({
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
        nuvoToken.safeTransferFrom(_owner, address(this), _amount);
        totalLocked += _amount;
        // record userAddr
        userIndex[_owner] = users.length;
        users.push(_owner);

        emit Locked(_owner, _amount, unlockTime);
    }

    /**
     * @dev Unlock NuoToken.
     */
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

    /**
     * @dev Add bonus point for user.
     * @param _userAddr The user address.
     */
    function accumulateBonusPoints(
        address _userAddr,
        uint256 _amount
    ) external onlyRole(ENTRYPOINT_ROLE) {
        require(locks[_userAddr].amount > 0, NotAUser(_userAddr));

        // Check if the reward period has ended and accumulate rewards if necessary
        if (getCurrentPeriod() > lastPeriodNumber) {
            accumulateRewards();
        }

        // Accumulate points
        locks[_userAddr].bonusPoints += _amount;
        totalBonusPoints += _amount;
    }

    /**
     * @dev Add demerit point for user
     * @param _userAddr The user address.
     */
    function accumulateDemeritPoints(
        address _userAddr,
        uint256 _amount
    ) external onlyRole(ENTRYPOINT_ROLE) {
        // Check if the reward period has ended and accumulate rewards if necessary
        if (getCurrentPeriod() > lastPeriodNumber) {
            accumulateRewards();
        }

        // Accumulate points
        locks[_userAddr].demeritPoints += _amount;
    }

    /**
     * @dev Calculate reward of each user for the last period
     */
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

    /**
     * @dev Claim rewards.
     */
    function claimRewards() external onlyUser {
        LockInfo storage lockInfo = locks[msg.sender];
        uint256 rewards = lockInfo.accumulatedRewards;
        require(rewards > 0, NothingToClaim());

        lockInfo.accumulatedRewards = 0;
        nuvoToken.safeTransferFrom(rewardSource, msg.sender, rewards);

        emit RewardsClaimed(msg.sender, rewards);
    }
}
