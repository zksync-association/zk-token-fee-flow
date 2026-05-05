set dotenv-load

era-fee-flow-deploy-mainnet:
  forge script script/EraFeeFlowDeploy.sol:EraFeeFlowDeploy --rpc-url "https://mainnet.era.zksync.io" --broadcast --skip-simulation --slow --verify --verifier zksync --verifier-url "https://zksync2-mainnet-explorer.zksync.io/contract_verification" --zksync

era-fee-flow-deploy-testnet:
  forge script script/EraFeeFlowDeploy.sol:EraFeeFlowDeploy --rpc-url "https://sepolia.era.zksync.dev" --broadcast --verify --verifier zksync --verifier-url "https://explorer.sepolia.era.zksync.dev/contract_verification" --zksync
