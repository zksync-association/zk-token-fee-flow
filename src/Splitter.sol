// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
  AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {
  UUPSUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Burnable} from "src/interfaces/IERC20Burnable.sol";

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

  /// @notice Emitted when the burn percentage is updated.
  /// @param oldBurnBps The previous burn percentage in basis points.
  /// @param newBurnBps The new burn percentage in basis points.
  event BurnPercentageSet(uint256 oldBurnBps, uint256 newBurnBps);

  /// @notice Thrown when an invalid address is provided where a valid address is required.
  error Splitter_InvalidAddress();

  /// @notice Thrown when caller lacks the required admin role for an operation.
  error Splitter_Unauthorized();

  /// @notice Thrown when a zero weight is provided.
  error Splitter_InvalidWeight();

  /// @notice Thrown when an invalid burn percentage is provided.
  error Splitter_InvalidBurnPercentage();

  /// @custom:storage-location erc7201:storage.Splitter
  struct SplitterStorage {
    IERC20Burnable _splitToken;
    uint256 _burnBps;
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
  /// @param _splitToken The token to be split and burned.
  /// @param _burnBps The initial burn percentage in basis points (must be 10000 if no
  /// distributors).
  /// @param _initialDistributors The initial set of distributors with weights.
  function initialize(
    address _admin,
    address _emergencyAdmin,
    IERC20Burnable _splitToken,
    uint256 _burnBps,
    DistributorConfig[] calldata _initialDistributors
  ) public initializer {
    if (_admin == address(0)) {
      revert Splitter_InvalidAddress();
    }
    if (_emergencyAdmin == address(0)) revert Splitter_InvalidAddress();

    __AccessControl_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(EMERGENCY_ADMIN_ROLE, _emergencyAdmin);

    SplitterStorage storage $ = _getSplitterStorage();
    $._splitToken = _splitToken;

    _setDistributors(_initialDistributors);
    _setBurnPercentage(_burnBps);
  }

  /// @notice Returns the token being split and burned.
  function splitToken() external view returns (IERC20Burnable) {
    SplitterStorage storage $ = _getSplitterStorage();
    return $._splitToken;
  }

  /// @notice Returns the burn percentage in basis points.
  function burnPercentage() external view returns (uint256) {
    SplitterStorage storage $ = _getSplitterStorage();
    return $._burnBps;
  }

  /// @notice Returns the distributed percentage in basis points (10000 - burnBps).
  function distributedPercentage() external view returns (uint256) {
    SplitterStorage storage $ = _getSplitterStorage();
    return 10_000 - $._burnBps;
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

  /// @notice Sets the burn percentage.
  /// @param _newBurnBps The new burn percentage in basis points (0-10000).
  function setBurnPercentage(uint256 _newBurnBps) external {
    _revertIfNotAdmin();
    _setBurnPercentage(_newBurnBps);
  }

  /// @notice Replaces the entire distributor configuration.
  /// @dev Empty array is allowed, which effectively pauses distribution and forces 100% burn.
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

  /// @dev Sets the burn percentage with validation and event emission.
  /// @param _newBurnBps The new burn percentage in basis points (0-10000).
  function _setBurnPercentage(uint256 _newBurnBps) internal {
    if (_newBurnBps > 10_000) revert Splitter_InvalidBurnPercentage();

    SplitterStorage storage $ = _getSplitterStorage();

    // If no distributors, burn must be 100%
    if ($._distributors.length == 0 && _newBurnBps != 10_000) {
      revert Splitter_InvalidBurnPercentage();
    }

    emit BurnPercentageSet($._burnBps, _newBurnBps);
    $._burnBps = _newBurnBps;
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

    // If clearing distributors, force burn to 100%
    if (_newDistributors.length == 0 && $._burnBps != 10_000) _setBurnPercentage(10_000);

    emit DistributorsSet(_newDistributors);
  }
}
