-include .env


.PHONY: build
build:
	forge build

.PHONY: install
install:
	forge install

# To deploy and verify our contract
deploy:
	forge script --chain sepolia script/Deploy.s.sol:Deploy --rpc-url sepolia --broadcast --verify -vvvv

deployTest:
	forge script --chain 48816 script/DeployTest.s.sol:DeployTest --rpc-url goatTestnet --broadcast -vvvv  --verify --verifier blockscout --verifier-url https://explorer.testnet3.goat.network/api/

deployDev:
	forge script --rpc-url localhost script/DeployTest.s.sol:DeployTest --broadcast -vvvv

participantSetup:
	forge script --rpc-url goatTestnet script/ParticipantSetup.s.sol:ParticipantSetup --broadcast -vvvv

mockData:
	forge script --rpc-url bscTestnet script/MockData.s.sol:MockData --broadcast -vvvv --verify 

.PHONY: abi
abi:
	mkdir -p abi
	forge inspect  AccountManagerUpgradeable abi > ./abi/AccountManager.json
	forge inspect  AssetManagerUpgradeable abi > ./abi/AssetManager.json
	forge inspect  DepositManagerUpgradeable abi > ./abi/DepositManager.json
	forge inspect  NIP20Upgradeable abi > ./abi/NIP20.json
	forge inspect  TaskManagerUpgradeable abi > ./abi/TaskManager.json
	forge inspect  NuvoDAOUpgradeable abi > ./abi/NuvoDao.json
	forge inspect  NuvoLockUpgradeable abi > ./abi/NuvoLock.json
	forge inspect  ParticipantManagerUpgradeable abi > ./abi/ParticipantManager.json
	forge inspect  EntryPointUpgradeable abi > ./abi/VotingManager.json
