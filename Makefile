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
	forge script --chain 48816 script/DeployTest.s.sol:DeployTest --rpc-url goatTestnet --broadcast -vvvv --verify --verifier blockscout --verifier-url https://explorer.testnet3.goat.network/api/

deployDev:
	forge script --rpc-url localhost script/DeployTest.s.sol:DeployTest --broadcast -vvvv

participantSetup:
	forge script --rpc-url goatTestnet script/ParticipantSetup.s.sol:ParticipantSetup --broadcast -vvvv

mockData:
	forge script --rpc-url localhost script/MockData.s.sol:MockData --broadcast -vvvv

mockData:
	forge script --rpc-url localhost script/MockDataLocal.s.sol:MockData --broadcast -vvvv

.PHONY: abi
abi:
	mkdir -p abi
	forge inspect  AccountHandlerUpgradeable abi > ./abi/AccountManager.json
	forge inspect  AssetHandlerUpgradeable abi > ./abi/AssetManager.json
	forge inspect  FundsHandlerUpgradeable abi > ./abi/FundManager.json
	forge inspect  TaskManagerUpgradeable abi > ./abi/TaskManager.json
	forge inspect  NuvoDAOUpgradeable abi > ./abi/NuvoDao.json
	forge inspect  NuvoLockUpgradeable abi > ./abi/NuvoLock.json
	forge inspect  ParticipantHandlerUpgradeable abi > ./abi/ParticipantManager.json
	forge inspect  EntryPointUpgradeable abi > ./abi/VotingManager.json

.PHONY: gen
gen:
	mkdir -p go
	abigen --abi=./abi/AccountManager.json --pkg=contracts --type AccountManagerContract --out=./go/account_manager.go
	abigen --abi=./abi/AssetManager.json --pkg=contracts --type AssetManagerContract --out=./go/asset_manager.go
	abigen --abi=./abi/FundManager.json --pkg=contracts --type FundManagerContract --out=./go/fund_manager.go
	abigen --abi=./abi/TaskManager.json --pkg=contracts --type TaskManagerContract --out=./go/task_manager.go
	abigen --abi=./abi/NuvoDao.json --pkg=contracts --type NuvoDaoContract --out=./go/nuvo_dao.go
	abigen --abi=./abi/NuvoLock.json --pkg=contracts --type NuvoLockContract --out=./go/nuvo_lock.go
	abigen --abi=./abi/ParticipantManager.json --type ParticipantManagerContract --pkg=contracts --out=./go/participant_manager.go
	abigen --abi=./abi/VotingManager.json --type VotingManagerContract --pkg=contracts --out=./go/voting_manager.go