// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {FeeFlow} from "src/FeeFlow.sol";
import {Splitter} from "src/Splitter.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Burnable} from "src/interfaces/IERC20Burnable.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Deploy
/// @notice Deploys FeeFlow and Splitter behind ERC1967 proxies.
/// @dev Environment variables:
/// - `DEPLOYER_PRIVATE_KEY` (required)
/// - `EXPECTED_CHAIN_ID` (optional; if set, reverts when `block.chainid` mismatches)
/// - `ADMIN` (optional; defaults to deployer address)
/// - `EMERGENCY_ADMIN` (optional; defaults to `ADMIN`)
/// - `BID_TOKEN` (required)
/// - `MIN_BID_THRESHOLD` (required)
/// - `BID_THRESHOLD` (required; must be >= `MIN_BID_THRESHOLD`)
/// - `SPLITTER_BURN_BPS` (optional; defaults to 10_000)
/// - `CLAIMABLE_TOKENS` (optional; comma-separated list of ERC20 addresses)
/// - `DISTRIBUTOR_RECIPIENTS` (optional; comma-separated list of addresses)
/// - `DISTRIBUTOR_WEIGHTS` (optional; comma-separated list of uint256 weights; same length as
///   `DISTRIBUTOR_RECIPIENTS`)
contract Deploy is Script {
  error Deploy_InvalidChainId(uint256 expected, uint256 actual);
  error Deploy_BidThresholdBelowMin(uint256 minBidThreshold, uint256 bidThreshold);
  error Deploy_InvalidBurnBps(uint256 burnBps);
  error Deploy_DistributorLengthMismatch(uint256 recipientsLength, uint256 weightsLength);
  error Deploy_DistributorWeightZero(uint256 index);

  struct DeploymentParams {
    address admin;
    address emergencyAdmin;
    IERC20Burnable bidToken;
    uint256 minBidThreshold;
    uint256 bidThreshold;
    uint256 burnBps;
    Splitter.DistributorConfig[] distributors;
    IERC20[] claimableTokens;
  }

  struct DeploymentResult {
    address splitterImplementation;
    address splitterProxy;
    address feeFlowImplementation;
    address feeFlowProxy;
  }

  /// @notice Entrypoint for `forge script`.
  /// @dev Loads config from env and deploys all contracts in one broadcast.
  function run() public returns (DeploymentResult memory _result) {
    uint256 _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    uint256 _expectedChainId = vm.envOr("EXPECTED_CHAIN_ID", uint256(0));
    if (_expectedChainId != 0 && block.chainid != _expectedChainId) {
      revert Deploy_InvalidChainId(_expectedChainId, block.chainid);
    }

    DeploymentParams memory _params = _getDeploymentParams(_deployerPrivateKey);

    vm.startBroadcast(_deployerPrivateKey);
    _result = _deploy(_params);
    vm.stopBroadcast();
  }

  /// @notice Build deployment params from environment variables.
  function _getDeploymentParams(uint256 _deployerPrivateKey)
    internal
    view
    returns (DeploymentParams memory)
  {
    address _deployer = vm.addr(_deployerPrivateKey);
    address _admin = vm.envOr("ADMIN", _deployer);

    address _bidToken = vm.envAddress("BID_TOKEN");
    uint256 _minBidThreshold = vm.envUint("MIN_BID_THRESHOLD");
    uint256 _bidThreshold = vm.envUint("BID_THRESHOLD");
    uint256 _burnBps = vm.envOr("SPLITTER_BURN_BPS", uint256(10_000));

    if (_bidThreshold < _minBidThreshold) {
      revert Deploy_BidThresholdBelowMin(_minBidThreshold, _bidThreshold);
    }
    if (_burnBps > 10_000) revert Deploy_InvalidBurnBps(_burnBps);

    return DeploymentParams({
      admin: _admin,
      emergencyAdmin: vm.envOr("EMERGENCY_ADMIN", _admin),
      bidToken: IERC20Burnable(_bidToken),
      minBidThreshold: _minBidThreshold,
      bidThreshold: _bidThreshold,
      burnBps: _burnBps,
      distributors: _distributorsFromEnv(),
      claimableTokens: _claimableTokensFromEnv()
    });
  }

  /// @notice Deploys the Splitter and FeeFlow contracts with proxies.
  function _deploy(DeploymentParams memory _params)
    internal
    returns (DeploymentResult memory _result)
  {
    Splitter _splitterImplementation = new Splitter();
    ERC1967Proxy _splitterProxy = new ERC1967Proxy(
      address(_splitterImplementation),
      abi.encodeCall(
        Splitter.initialize,
        (
          _params.admin,
          _params.emergencyAdmin,
          _params.bidToken,
          _params.burnBps,
          _params.distributors
        )
      )
    );

    FeeFlow _feeFlowImplementation = new FeeFlow();
    ERC1967Proxy _feeFlowProxy = new ERC1967Proxy(
      address(_feeFlowImplementation),
      abi.encodeCall(
        FeeFlow.initialize,
        (
          _params.admin,
          _params.emergencyAdmin,
          IERC20(address(_params.bidToken)),
          _params.minBidThreshold,
          _params.bidThreshold,
          address(_splitterProxy),
          _params.claimableTokens
        )
      )
    );

    return DeploymentResult({
      splitterImplementation: address(_splitterImplementation),
      splitterProxy: address(_splitterProxy),
      feeFlowImplementation: address(_feeFlowImplementation),
      feeFlowProxy: address(_feeFlowProxy)
    });
  }

  function _claimableTokensFromEnv() internal view returns (IERC20[] memory claimableTokens) {
    address[] memory _claimableTokenAddresses = vm.envOr("CLAIMABLE_TOKENS", ",", new address[](0));
    claimableTokens = new IERC20[](_claimableTokenAddresses.length);
    for (uint256 _i; _i < _claimableTokenAddresses.length; ++_i) {
      claimableTokens[_i] = IERC20(_claimableTokenAddresses[_i]);
    }
  }

  function _distributorsFromEnv() internal view returns (Splitter.DistributorConfig[] memory) {
    address[] memory _recipients = vm.envOr("DISTRIBUTOR_RECIPIENTS", ",", new address[](0));
    uint256[] memory _weights = vm.envOr("DISTRIBUTOR_WEIGHTS", ",", new uint256[](0));

    if (_recipients.length != _weights.length) {
      revert Deploy_DistributorLengthMismatch(_recipients.length, _weights.length);
    }

    Splitter.DistributorConfig[] memory _distributors =
      new Splitter.DistributorConfig[](_recipients.length);
    for (uint256 _i; _i < _recipients.length; ++_i) {
      if (_weights[_i] == 0) revert Deploy_DistributorWeightZero(_i);
      _distributors[_i] =
        Splitter.DistributorConfig({recipient: _recipients[_i], weight: uint96(_weights[_i])});
    }
    return _distributors;
  }
}
