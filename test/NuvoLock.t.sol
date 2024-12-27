// pragma solidity ^0.8.0;

// import "./BaseTest.sol";

// import {INuvoLock} from "../src/interfaces/INuvoLock.sol";

// contract NuvoLockTest is BaseTest {
//     address public user;

//     address public nuvoLockProxy;

//     function setUp() public override {
//         super.setUp();

//         address rewardSource = makeAddr("rewardSource");
//         nuvoToken.mint(rewardSource, 100 ether);
//         // deploy NuvoLockUpgradeable
//         nuvoLockProxy = _deployProxy(address(new NuvoLockUpgradeable()), daoContract);
//         nuvoLock = NuvoLockUpgradeable(nuvoLockProxy);
//         nuvoLock.initialize(
//             address(nuvoToken),
//             rewardSource,
//             vmProxy,
//             MIN_LOCK_AMOUNT,
//             MIN_LOCK_PERIOD
//         );
//         assertEq(nuvoLock.owner(), vmProxy);
//         vm.prank(rewardSource);
//         nuvoToken.approve(nuvoLockProxy, 100 ether);
//     }

//     function test_Lock() public {
//         vm.startPrank(msgSender);
//         // first participant
//         uint256 totalAmount = nuvoLock.totalLocked();
//         uint256 lockAmount = 1 ether;
//         uint32 lastPeriodNumber = nuvoLock.lastPeriodNumber();
//         assertEq(nuvoLock.lockedBalanceOf(msgSender), 0);

//         nuvoToken.approve(address(nuvoLock), lockAmount);
//         vm.expectEmit(true, true, true, true);
//         emit INuvoLock.Locked(msgSender, lockAmount, uint32(block.timestamp + MIN_LOCK_PERIOD));
//         nuvoLock.lock(lockAmount, MIN_LOCK_PERIOD);
//         totalAmount += lockAmount;

//         assertEq(nuvoToken.balanceOf(address(nuvoLock)), totalAmount);
//         assertEq(nuvoLock.totalLocked(), totalAmount);
//         assertEq(nuvoLock.users(0), msgSender);
//         INuvoLock.LockInfo memory expectedLockInfo = INuvoLock.LockInfo({
//             amount: lockAmount,
//             unlockTime: uint32(block.timestamp + MIN_LOCK_PERIOD),
//             originalLockTime: MIN_LOCK_PERIOD,
//             startTime: uint32(block.timestamp),
//             bonusPoints: 0,
//             accumulatedRewards: 0,
//             lastClaimedPeriod: lastPeriodNumber,
//             demeritPoints: 0
//         });
//         {
//             (
//                 uint256 amount,
//                 uint32 unlockTime,
//                 uint32 originalLockTime,
//                 uint32 startTime,
//                 uint256 bonusPoints,
//                 uint256 accumulatedRewards,
//                 uint256 lastClaimedPeriod,
//                 uint256 demeritPoints
//             ) = nuvoLock.locks(msgSender);
//             assertEq(
//                 abi.encode(expectedLockInfo),
//                 abi.encode(
//                     amount,
//                     unlockTime,
//                     originalLockTime,
//                     startTime,
//                     bonusPoints,
//                     accumulatedRewards,
//                     lastClaimedPeriod,
//                     demeritPoints
//                 )
//             );
//         }

//         // second participant
//         address user2 = makeAddr("user2");
//         lockAmount = 2 ether;
//         nuvoToken.transfer(user2, lockAmount);
//         vm.startPrank(user2);
//         nuvoToken.approve(address(nuvoLock), lockAmount);
//         vm.expectEmit(true, true, true, true);
//         emit INuvoLock.Locked(user2, lockAmount, uint32(block.timestamp + MIN_LOCK_PERIOD));
//         nuvoLock.lock(lockAmount, MIN_LOCK_PERIOD);
//         totalAmount += lockAmount;

//         assertEq(nuvoToken.balanceOf(address(nuvoLock)), totalAmount);
//         assertEq(nuvoLock.totalLocked(), totalAmount);
//         assertEq(nuvoLock.users(1), user2);
//         expectedLockInfo = INuvoLock.LockInfo({
//             amount: lockAmount,
//             unlockTime: uint32(block.timestamp + MIN_LOCK_PERIOD),
//             originalLockTime: MIN_LOCK_PERIOD,
//             startTime: uint32(block.timestamp),
//             bonusPoints: 0,
//             accumulatedRewards: 0,
//             lastClaimedPeriod: lastPeriodNumber,
//             demeritPoints: 0
//         });
//         {
//             (
//                 uint32 unlockTime,
//                 uint32 originalLockTime,
//                 uint32 startTime,
//                 uint32 lastClaimedPeriod,
//                 uint256 amount,
//                 uint256 bonusPoints,
//                 uint256 accumulatedRewards,
//                 uint256 demeritPoints
//             ) = nuvoLock.locks(user2);
//             assertEq(
//                 abi.encode(expectedLockInfo),
//                 abi.encode(
//                     unlockTime,
//                     originalLockTime,
//                     startTime,
//                     lastClaimedPeriod,
//                     amount,
//                     bonusPoints,
//                     accumulatedRewards,
//                     demeritPoints
//                 )
//             );
//         }
//         // check locked time
//         skip(1 days);
//         assertEq(nuvoLock.lockedTime(msgSender), 1 days);

//         vm.stopPrank();
//     }

//     function test_LockRevert() public {
//         vm.startPrank(msgSender);
//         uint256 lockAmount = 1 ether;
//         // fail case: amount = 0
//         vm.expectRevert(abi.encodeWithSelector(INuvoLock.AmountBelowMin.selector, 0));
//         nuvoLock.lock(0, MIN_LOCK_PERIOD);
//         // fail case: lock period less than the minLockPeriod
//         vm.expectRevert(
//             abi.encodeWithSelector(INuvoLock.TimePeriodBelowMin.selector, MIN_LOCK_PERIOD - 1)
//         );
//         nuvoLock.lock(lockAmount, MIN_LOCK_PERIOD - 1);
//         // fail case: did not approve before lock
//         vm.expectRevert(
//             abi.encodeWithSelector(
//                 bytes4(keccak256("ERC20InsufficientAllowance(address,uint256,uint256)")),
//                 address(nuvoLock),
//                 0,
//                 lockAmount
//             )
//         );
//         nuvoLock.lock(lockAmount, MIN_LOCK_PERIOD);
//         // fail case: insufficient balance
//         nuvoToken.transfer(thisAddr, nuvoToken.balanceOf(msgSender));
//         nuvoToken.approve(address(nuvoLock), lockAmount);
//         vm.expectRevert(
//             abi.encodeWithSelector(
//                 bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)")),
//                 msgSender,
//                 0,
//                 lockAmount
//             )
//         );
//         nuvoLock.lock(lockAmount, MIN_LOCK_PERIOD);

//         // success
//         nuvoToken.mint(msgSender, lockAmount);
//         nuvoToken.approve(address(nuvoLock), lockAmount);
//         nuvoLock.lock(lockAmount, MIN_LOCK_PERIOD);

//         // fail case: already locked
//         vm.expectRevert(abi.encodeWithSelector(INuvoLock.AlreadyLocked.selector, msgSender));
//         nuvoLock.lock(lockAmount, MIN_LOCK_PERIOD);
//         vm.stopPrank();
//     }

//     function test_Unlock() public {
//         vm.startPrank(msgSender);
//         // setup
//         uint256 lockAmount = 1 ether;
//         nuvoToken.approve(address(nuvoLock), lockAmount);
//         nuvoLock.lock(lockAmount, MIN_LOCK_PERIOD);

//         // unlock
//         skip(MIN_LOCK_PERIOD);
//         assertEq(nuvoLock.lockedBalanceOf(msgSender), lockAmount);
//         vm.expectEmit(true, true, true, true);
//         emit INuvoLock.Unlocked(msgSender, lockAmount);
//         nuvoLock.unlock();
//         assertEq(nuvoLock.lockedBalanceOf(msgSender), 0);
//         vm.stopPrank();
//     }

//     function test_UnlockRevert() public {
//         vm.startPrank(msgSender);
//         // fail case: unlock before lock, not a user
//         vm.expectRevert(abi.encodeWithSelector(INuvoLock.NotAUser.selector, msgSender));
//         nuvoLock.unlock();
//         // setup
//         uint256 lockAmount = 1 ether;
//         nuvoToken.approve(address(nuvoLock), lockAmount);
//         nuvoLock.lock(lockAmount, MIN_LOCK_PERIOD);

//         // fail case: have not pass the unlock time
//         (uint32 unlockTime, , , , , , , ) = nuvoLock.locks(msgSender);
//         vm.expectRevert(
//             abi.encodeWithSelector(
//                 INuvoLock.UnlockedTimeNotReached.selector,
//                 block.timestamp,
//                 unlockTime
//             )
//         );
//         nuvoLock.unlock();
//         vm.stopPrank();

//         skip(MIN_LOCK_PERIOD);
//         // fail case: insuficient token
//         vm.prank(address(nuvoLock));
//         nuvoToken.transfer(thisAddr, lockAmount);
//         vm.prank(msgSender);
//         vm.expectRevert(
//             abi.encodeWithSelector(
//                 bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)")),
//                 address(nuvoLock),
//                 0,
//                 lockAmount
//             )
//         );
//         nuvoLock.unlock();
//         vm.stopPrank();
//     }

//     function test_OwnerFunction() public {
//         vm.startPrank(msgSender);
//         uint64 taskId = taskSubmitter.submitTask(_generateTaskContext());
//         nuvoToken.approve(address(nuvoLock), MIN_LOCK_AMOUNT);
//         nuvoLock.lock(MIN_LOCK_AMOUNT, MIN_LOCK_PERIOD);

//         assertEq(nuvoLock.minLockAmount(), MIN_LOCK_AMOUNT);
//         assertEq(nuvoLock.minLockPeriod(), MIN_LOCK_PERIOD);
//         uint256 newLockAmount = 10 ether;
//         uint256 newLockPeriod = 10 days;
//         bytes memory callData = abi.encodeWithSelector(
//             INuvoLock.setMinLockInfo.selector,
//             newLockAmount,
//             newLockPeriod
//         );
//         Operation[] memory opts = new Operation[](1);
//         opts[0] = Operation(nuvoLockProxy, State.Completed, taskId, callData);
//         signature = _generateOptSignature(opts, tssKey);
//         vm.expectEmit(true, true, true, true);
//         emit INuvoLock.MinLockInfo(newLockAmount, newLockPeriod);
//         entryPoint.verifyAndCall(opts, signature);
//         assertEq(nuvoLock.minLockAmount(), newLockAmount);
//         assertEq(nuvoLock.minLockPeriod(), newLockPeriod);

//         vm.stopPrank();
//         skip(1 weeks);
//         vm.startPrank(vmProxy);
//         nuvoLock.accumulateBonusPoints(msgSender, 1);
//         (, , , , , uint256 bonusPoints, , ) = nuvoLock.locks(msgSender);
//         assertEq(bonusPoints, 2);
//         skip(1 weeks);
//         nuvoLock.accumulateDemeritPoints(msgSender, 1);
//         (, , , , , , , uint256 demeritPoint) = nuvoLock.locks(msgSender);
//         assertEq(demeritPoint, 1);
//     }

//     function test_RewardPoint() public {
//         vm.startPrank(msgSender);
//         uint64 taskId = taskSubmitter.submitTask(_generateTaskContext());
//         nuvoToken.approve(address(nuvoLock), MIN_LOCK_AMOUNT);
//         nuvoLock.lock(MIN_LOCK_AMOUNT, MIN_LOCK_PERIOD);

//         uint32 lastPeriodNumber = nuvoLock.lastPeriodNumber();
//         assertEq(lastPeriodNumber, nuvoLock.getCurrentPeriod());
//         assertEq(nuvoLock.rewardPerPeriod(lastPeriodNumber), 0);
//         uint256 newRewardPerPeriod = 3 ether;
//         bytes memory callData = abi.encodeWithSelector(
//             INuvoLock.setRewardPerPeriod.selector,
//             newRewardPerPeriod
//         );
//         Operation[] memory opts = new Operation[](1);
//         opts[0] = Operation(nuvoLockProxy, State.Completed, taskId, callData);
//         signature = _generateOptSignature(opts, tssKey);

//         vm.expectEmit(true, true, true, true);
//         emit INuvoLock.RewardPerPeriodUpdated(newRewardPerPeriod, lastPeriodNumber);
//         entryPoint.verifyAndCall(opts, signature);
//         assertEq(nuvoLock.rewardPerPeriod(lastPeriodNumber), newRewardPerPeriod);
//         {
//             (, , , , , uint256 bonusPoints, , ) = nuvoLock.locks(msgSender);
//             assertEq(bonusPoints, 1);
//             assertEq(nuvoLock.totalBonusPoints(), bonusPoints);
//         }
//         uint256 snapshot = vm.snapshot();

//         // get ready for accumulateRewards()
//         skip(2 weeks);
//         assert(
//             lastPeriodNumber < nuvoLock.getCurrentPeriod() &&
//                 nuvoLock.totalBonusPoints() > 0 &&
//                 nuvoLock.rewardPerPeriod(lastPeriodNumber) > 0
//         );

//         vm.expectEmit(true, true, true, true);
//         emit INuvoLock.RewardsAccumulated(msgSender, newRewardPerPeriod);
//         nuvoLock.accumulateRewards();
//         assert(lastPeriodNumber < nuvoLock.getCurrentPeriod());
//         assertEq(nuvoLock.lastPeriodNumber(), nuvoLock.getCurrentPeriod());
//         {
//             (, , , , , uint256 bonusPoints, uint256 accumulatedRewards, ) = nuvoLock.locks(
//                 msgSender
//             );
//             assertEq(bonusPoints, 0);
//             assertEq(accumulatedRewards, newRewardPerPeriod);
//             assertEq(nuvoLock.totalBonusPoints(), 0);
//         }
//         uint256 initialBal = nuvoToken.balanceOf(msgSender);
//         nuvoLock.claimRewards();
//         assertEq(nuvoToken.balanceOf(msgSender), initialBal + newRewardPerPeriod);

//         vm.stopPrank();

//         // when demeritPoint is applied
//         vm.revertTo(snapshot);
//         vm.prank(vmProxy);
//         nuvoLock.accumulateDemeritPoints(msgSender, 1);
//         {
//             (, , , , , uint256 bonusPoints, , uint256 demeritPoints) = nuvoLock.locks(msgSender);
//             assertEq(bonusPoints, 1);
//             assertEq(demeritPoints, 1);
//         }
//         skip(2 weeks);
//         vm.prank(msgSender);
//         nuvoLock.accumulateRewards();
//         {
//             (
//                 ,
//                 ,
//                 ,
//                 ,
//                 ,
//                 uint256 bonusPoints,
//                 uint256 accumulatedRewards,
//                 uint256 demeritPoints
//             ) = nuvoLock.locks(msgSender);
//             assertEq(bonusPoints, 0);
//             assertEq(accumulatedRewards, 0);
//             assertEq(demeritPoints, 0);
//         }
//     }

//     function test_RewardRevert() public {
//         vm.prank(msgSender);
//         uint64 taskId = taskSubmitter.submitTask(_generateTaskContext());
//         uint256 newRewardPerPeriod = 3 ether;
//         bytes memory callData = abi.encodeWithSelector(
//             INuvoLock.setRewardPerPeriod.selector,
//             newRewardPerPeriod
//         );
//         Operation[] memory opts = new Operation[](1);
//         opts[0] = Operation(nuvoLockProxy, State.Completed, taskId, callData);
//         signature = _generateOptSignature(opts, tssKey);

//         vm.prank(msgSender);
//         vm.expectRevert(abi.encodeWithSelector(INuvoLock.NotAUser.selector, msgSender));
//         entryPoint.verifyAndCall(opts, signature);

//         vm.startPrank(msgSender);
//         nuvoToken.approve(address(nuvoLock), MIN_LOCK_AMOUNT);
//         nuvoLock.lock(MIN_LOCK_AMOUNT, MIN_LOCK_PERIOD);

//         (, , , , , uint256 accumulatedRewards, , ) = nuvoLock.locks(msgSender);
//         assertEq(accumulatedRewards, 0);
//         vm.expectRevert(INuvoLock.NothingToClaim.selector);
//         nuvoLock.claimRewards();

//         vm.stopPrank();
//     }
// }
