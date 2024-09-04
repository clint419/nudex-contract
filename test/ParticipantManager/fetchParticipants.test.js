const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ParticipantManager - Fetching Participants", function () {
  let participantManager, nuvoLock, owner, addr1, addr2, addr3;

  beforeEach(async function () {
    [owner, addr1, addr2, addr3] = await ethers.getSigners();
    address1 = await addr1.getAddress();
    address2 = await addr2.getAddress();

    // Deploy mock NuvoLockUpgradeable
    const MockNuvoLockUpgradeable = await ethers.getContractFactory("MockNuvoLockUpgradeable");
    nuvoLock = await MockNuvoLockUpgradeable.deploy();
    await nuvoLock.waitForDeployment();

    // Deploy ParticipantManager
    const ParticipantManager = await ethers.getContractFactory("ParticipantManager");
    participantManager = await upgrades.deployProxy(
      ParticipantManager,
      [await nuvoLock.getAddress(), 100, 7 * 24 * 60 * 60, await owner.getAddress()],
      { initializer: "initialize" }
    );
    await participantManager.waitForDeployment();

    // Add participants
    await participantManager.addParticipant(address1);
    await participantManager.addParticipant(address2);
    await participantManager.addParticipant(addr3.address);
  });

  it("Should return the correct list of participants", async function () {
    const participants = await participantManager.getParticipants();
    expect(participants.length).to.equal(3);
    expect(participants).to.include.members([address1, address2, addr3.address]);
  });

  it("Should return an empty list when no participants are present", async function () {
    // Remove all participants
    await participantManager.removeParticipant(address1);
    await participantManager.removeParticipant(address2);
    await participantManager.removeParticipant(addr3.address);

    const participants = await participantManager.getParticipants();
    expect(participants.length).to.equal(0);
  });
});
