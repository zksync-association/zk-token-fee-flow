// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title FeeFlow
/// @author ScopeLift
/// @notice A contract where bid tokens are exchanged for accumulated fee assets via a fixed-price
/// auction. As fees accumulate, it will make economic sense for a bidder to bid once the value of
/// the accrued assets exceeds the fixed bid token value. The bid tokens received are forwarded to a
/// destination address.
/// @dev In ZKsync's deployment, the bid token is ZK and the destination is a Splitter contract.
/// @custom:security-contact security@matterlabs.dev
contract FeeFlow is AccessControl {
  /// @notice Role identifier for emergency admin who can pause the contract without governance
  /// delay.
  bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN_ROLE");

  /// @notice The token used for bidding in the fee auction.
  IERC20 public immutable BID_TOKEN;

  /// @notice The amount of bid tokens required to claim accumulated fee assets.
  uint256 public bidThreshold;

  /// @notice The destination address where bid tokens are forwarded after claims.
  /// @dev In ZKsync's deployment, this is a Splitter contract.
  address public destination;

  /// @notice Emitted when the bid threshold is updated.
  event BidThresholdSet(uint256 oldThreshold, uint256 newThreshold);

  /// @notice Emitted when the destination address is updated.
  event DestinationSet(address oldDestination, address newDestination);

  /// @notice Thrown when an invalid address is provided where a valid address is required.
  error FeeFlow_InvalidAddress();

  /// @notice Thrown when caller lacks the required admin role for an operation.
  error FeeFlow_Unauthorized();

  /// @param _admin The address that receives the DEFAULT_ADMIN_ROLE (governance).
  /// @param _emergencyAdmin The address that receives the EMERGENCY_ADMIN_ROLE (emergency board).
  /// @param _bidToken The token contract used for auction payments.
  constructor(address _admin, address _emergencyAdmin, IERC20 _bidToken) {
    if (_admin == address(0)) revert FeeFlow_InvalidAddress();
    if (_emergencyAdmin == address(0)) revert FeeFlow_InvalidAddress();

    BID_TOKEN = _bidToken;

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(EMERGENCY_ADMIN_ROLE, _emergencyAdmin);
  }

  /// @notice Sets the bid threshold required to claim fee assets.
  /// @param _newThreshold The new threshold amount.
  function setBidThreshold(uint256 _newThreshold) external {
    _revertIfNotAdmin();
    emit BidThresholdSet(bidThreshold, _newThreshold);
    bidThreshold = _newThreshold;
  }

  /// @notice Sets the destination address where bid tokens are forwarded.
  /// @param _newDestination The new destination address.
  function setDestination(address _newDestination) external {
    _revertIfNotAdmin();
    if (_newDestination == address(0)) revert FeeFlow_InvalidAddress();
    emit DestinationSet(destination, _newDestination);
    destination = _newDestination;
  }

  /// @dev Reverts if the caller does not have `DEFAULT_ADMIN_ROLE` or `EMERGENCY_ADMIN_ROLE`.
  function _revertIfNotAdmin() internal view {
    if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender) && !hasRole(EMERGENCY_ADMIN_ROLE, msg.sender)) {
      revert FeeFlow_Unauthorized();
    }
  }
}
