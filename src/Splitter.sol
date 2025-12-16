// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
  AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {
  UUPSUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title Splitter
/// @author ScopeLift
/// @notice A contract that splits tokens between weighted distributors and burning.
/// @dev In ZKsync's deployment, this contract receives ZK tokens from FeeFlow and distributes them
/// to configured distributors based on their weights.
/// @custom:security-contact security@matterlabs.dev
contract Splitter is AccessControlUpgradeable, UUPSUpgradeable {
  /// @notice Role identifier for emergency admin who can update settings without governance delay.
  bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN_ROLE");

  /// @notice A distributor configuration with recipient address and weight.
  /// @param recipient The address that will receive distributed tokens.
  /// @param weight The relative weight determining the recipient's share of distributions.
  struct DistributorConfig {
    address recipient;
    uint96 weight;
  }

  /// @notice Emitted when the distributor configuration is replaced.
  /// @param distributors The new distributor configuration.
  event DistributorsSet(DistributorConfig[] distributors);

  /// @notice Thrown when an invalid address is provided where a valid address is required.
  error Splitter_InvalidAddress();

  /// @notice Thrown when caller lacks the required admin role for an operation.
  error Splitter_Unauthorized();

  /// @notice Thrown when a zero weight is provided.
  error Splitter_InvalidWeight();

  /// @custom:storage-location erc7201:storage.Splitter
  struct SplitterStorage {
    uint256 _totalWeight;
    DistributorConfig[] _distributors;
  }

  // keccak256(abi.encode(uint256(keccak256("storage.Splitter")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 public constant SPLITTER_STORAGE_LOCATION =
    0xbdd5a47cbec2cdef1dc4ed3652cf59ca3f94f5bee32f69b90eb705174d5f0200;

  function _getSplitterStorage() private pure returns (SplitterStorage storage $) {
    assembly {
      $.slot := SPLITTER_STORAGE_LOCATION
    }
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes the Splitter contract.
  /// @param _admin The address that can update settings and authorize upgrades.
  /// @param _emergencyAdmin The address that can update settings in emergencies.
  /// @param _initialDistributors The initial set of distributors with weights.
  function initialize(
    address _admin,
    address _emergencyAdmin,
    DistributorConfig[] calldata _initialDistributors
  ) public initializer {
    if (_admin == address(0)) revert Splitter_InvalidAddress();
    if (_emergencyAdmin == address(0)) revert Splitter_InvalidAddress();

    __AccessControl_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(EMERGENCY_ADMIN_ROLE, _emergencyAdmin);

    _setDistributors(_initialDistributors);
  }

  /// @notice Returns the total weight of all distributors.
  function totalDistributorWeight() external view returns (uint256) {
    SplitterStorage storage $ = _getSplitterStorage();
    return $._totalWeight;
  }

  /// @notice Returns the list of all distributors with their weights.
  function distributors() external view returns (DistributorConfig[] memory) {
    SplitterStorage storage $ = _getSplitterStorage();
    return $._distributors;
  }

  /// @notice Replaces the entire distributor configuration.
  /// @dev Empty array is allowed, which effectively pauses distribution.
  /// Duplicate recipients are allowed and will each receive their allocated share.
  /// @param _newDistributors The new set of distributors with weights.
  function setDistributors(DistributorConfig[] calldata _newDistributors) external {
    _revertIfNotAdmin();
    _setDistributors(_newDistributors);
  }

  /// @dev Authorizes an upgrade to a new implementation.
  /// @dev Only the admin can authorize upgrades.
  function _authorizeUpgrade(address) internal view override {
    _revertIfNotDefaultAdmin();
  }

  /// @dev Reverts if the caller is not the admin or emergency admin.
  function _revertIfNotAdmin() internal view {
    if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender) && !hasRole(EMERGENCY_ADMIN_ROLE, msg.sender)) {
      revert Splitter_Unauthorized();
    }
  }

  /// @dev Reverts if the caller is not the admin.
  function _revertIfNotDefaultAdmin() internal view {
    if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert Splitter_Unauthorized();
  }

  /// @dev Sets the distributor configuration and emits an event.
  /// @param _newDistributors The new set of distributors with weights.
  function _setDistributors(DistributorConfig[] calldata _newDistributors) internal {
    SplitterStorage storage $ = _getSplitterStorage();

    // Clear existing distributors
    delete $._distributors;

    // Add new distributors and compute total weight
    uint256 _newTotalWeight;
    for (uint256 _i; _i < _newDistributors.length; ++_i) {
      if (_newDistributors[_i].recipient == address(0)) revert Splitter_InvalidAddress();
      if (_newDistributors[_i].weight == 0) revert Splitter_InvalidWeight();

      $._distributors.push(_newDistributors[_i]);
      _newTotalWeight += _newDistributors[_i].weight;
    }

    $._totalWeight = _newTotalWeight;
    emit DistributorsSet(_newDistributors);
  }
}
