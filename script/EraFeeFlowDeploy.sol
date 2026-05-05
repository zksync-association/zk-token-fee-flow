// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseFeeFlowDeploy} from "script/BaseFeeFlowDeploy.sol";
import {Splitter} from "src/Splitter.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Burnable} from "src/interfaces/IERC20Burnable.sol";

/// @title EraFeeFlowDeploy
/// @notice ZKsync Era mainnet configuration for the FeeFlow deployment.
/// @dev Environment variables:
/// - `DEPLOYER_PRIVATE_KEY` (required)
contract EraFeeFlowDeploy is BaseFeeFlowDeploy {
  address public constant ZK_TOKEN = 0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E;
  address public constant WETH = 0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91;
  address public constant BRIDGED_USDC = 0x3355df6D4c9C3035724Fd0e3914dE96A5a83aaf4;
  address public constant USDC = 0x1d17CBcF0D6D143135aE902365D2E5e2A16538D4;
  address public constant EMERGENCY_ADMIN = 0x9BdC9Ff6b5E33914b84C1fb7D695c67fF9E7c8B7;
  address public constant TOKEN_GOVERNOR_TIMELOCK = 0xe5d21A9179CA2E1F0F327d598D464CcF60d89c3d;
  uint256 public constant MIN_BID_THRESHOLD = 100_000e18;
  uint256 public constant BID_THRESHOLD = 1_000_000e18;

  function _getSplitterConfig() public pure override returns (SplitterParams memory) {
    return SplitterParams({
      admin: TOKEN_GOVERNOR_TIMELOCK,
      emergencyAdmin: EMERGENCY_ADMIN,
      splitToken: IERC20Burnable(ZK_TOKEN),
      burnBps: 10_000,
      distributors: _getDistributors()
    });
  }

  function _getFeeFlowConfig(address _splitterProxy)
    public
    pure
    override
    returns (FeeFlowParams memory)
  {
    return FeeFlowParams({
      admin: TOKEN_GOVERNOR_TIMELOCK,
      emergencyAdmin: EMERGENCY_ADMIN,
      bidToken: IERC20(ZK_TOKEN),
      minBidThreshold: MIN_BID_THRESHOLD,
      bidThreshold: BID_THRESHOLD,
      destination: _splitterProxy,
      claimableTokens: _getClaimableTokens()
    });
  }

  function _getClaimableTokens() internal pure returns (IERC20[] memory _claimableTokens) {
    _claimableTokens = new IERC20[](3);
    _claimableTokens[0] = IERC20(WETH);
    _claimableTokens[1] = IERC20(BRIDGED_USDC);
    _claimableTokens[2] = IERC20(USDC);
  }

  function _getDistributors() internal pure returns (Splitter.DistributorConfig[] memory) {
    return new Splitter.DistributorConfig[](0);
  }
}
