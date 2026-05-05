// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {FeeFlow} from "src/FeeFlow.sol";
import {Splitter} from "src/Splitter.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Burnable} from "src/interfaces/IERC20Burnable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title BaseFeeFlowDeploy
/// @notice Shared deployment flow for FeeFlow and Splitter ERC1967 proxy deployments.
abstract contract BaseFeeFlowDeploy is Script {
  error BaseFeeFlowDeploy_BidThresholdBelowMin(uint256 minBidThreshold, uint256 bidThreshold);
  error BaseFeeFlowDeploy_InvalidBurnBps(uint256 burnBps);

  Splitter public splitter;
  FeeFlow public feeFlow;
  address public deployer;
  uint256 public deployerPrivateKey;

  struct SplitterParams {
    address admin;
    address emergencyAdmin;
    IERC20Burnable splitToken;
    uint256 burnBps;
    Splitter.DistributorConfig[] distributors;
  }

  struct FeeFlowParams {
    address admin;
    address emergencyAdmin;
    IERC20 bidToken;
    uint256 minBidThreshold;
    uint256 bidThreshold;
    address destination;
    IERC20[] claimableTokens;
  }

  struct DeploymentResult {
    address splitterImplementation;
    address splitterProxy;
    address feeFlowImplementation;
    address feeFlowProxy;
  }

  function setUp() public virtual {
    deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    deployer = vm.rememberKey(deployerPrivateKey);

    console2.log("Deploying from:", deployer);
  }

  function _getSplitterConfig() public view virtual returns (SplitterParams memory);

  function _getFeeFlowConfig(address _splitterProxy)
    public
    view
    virtual
    returns (FeeFlowParams memory);

  function run() public virtual returns (DeploymentResult memory _result) {
    SplitterParams memory _splitterParams = _getSplitterConfig();
    _validateSplitterParams(_splitterParams);

    vm.broadcast(deployer);
    Splitter _splitterImplementation = new Splitter();
    console2.log("Deployed Splitter implementation:", address(_splitterImplementation));

    vm.broadcast(deployer);
    ERC1967Proxy _splitterProxy = new ERC1967Proxy(
      address(_splitterImplementation),
      abi.encodeCall(
        Splitter.initialize,
        (
          _splitterParams.admin,
          _splitterParams.emergencyAdmin,
          _splitterParams.splitToken,
          _splitterParams.burnBps,
          _splitterParams.distributors
        )
      )
    );
    splitter = Splitter(address(_splitterProxy));
    console2.log("Deployed Splitter proxy:", address(splitter));

    FeeFlowParams memory _feeFlowParams = _getFeeFlowConfig(address(splitter));
    _validateFeeFlowParams(_feeFlowParams);

    vm.broadcast(deployer);
    FeeFlow _feeFlowImplementation = new FeeFlow();
    console2.log("Deployed FeeFlow implementation:", address(_feeFlowImplementation));

    vm.broadcast(deployer);
    ERC1967Proxy _feeFlowProxy = new ERC1967Proxy(
      address(_feeFlowImplementation),
      abi.encodeCall(
        FeeFlow.initialize,
        (
          _feeFlowParams.admin,
          _feeFlowParams.emergencyAdmin,
          _feeFlowParams.bidToken,
          _feeFlowParams.minBidThreshold,
          _feeFlowParams.bidThreshold,
          _feeFlowParams.destination,
          _feeFlowParams.claimableTokens
        )
      )
    );
    feeFlow = FeeFlow(address(_feeFlowProxy));
    console2.log("Deployed FeeFlow proxy:", address(feeFlow));

    return DeploymentResult({
      splitterImplementation: address(_splitterImplementation),
      splitterProxy: address(splitter),
      feeFlowImplementation: address(_feeFlowImplementation),
      feeFlowProxy: address(feeFlow)
    });
  }

  function _validateSplitterParams(SplitterParams memory _params) internal pure {
    if (_params.burnBps > 10_000) revert BaseFeeFlowDeploy_InvalidBurnBps(_params.burnBps);
  }

  function _validateFeeFlowParams(FeeFlowParams memory _params) internal pure {
    if (_params.bidThreshold < _params.minBidThreshold) {
      revert BaseFeeFlowDeploy_BidThresholdBelowMin(_params.minBidThreshold, _params.bidThreshold);
    }
  }
}
