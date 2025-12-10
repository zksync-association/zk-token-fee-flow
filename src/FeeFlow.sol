// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title FeeFlow
/// @author ScopeLift
/// @notice A contract where bid tokens are exchanged for accumulated fee assets via a fixed-price
/// auction. As fees accumulate, it will make economic sense for a bidder to bid once the value of
/// the accrued assets exceeds the fixed bid token value. The bid tokens received are forwarded to a
/// destination address.
/// @dev In ZKsync's deployment, the bid token is ZK and the destination is a Splitter contract.
/// @custom:security-contact security@matterlabs.dev
contract FeeFlow is AccessControl {
  using SafeERC20 for IERC20;

  /// @notice Role identifier for emergency admin who can pause the contract without governance
  /// delay.
  bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN_ROLE");

  /// @notice The token used for bidding in the fee auction.
  IERC20 public immutable BID_TOKEN;

  /// @notice The amount of bid tokens required to claim accumulated fee assets.
  uint256 public bidThreshold;

  /// @notice The minimum threshold that can be set for bid token claims.
  uint256 public immutable MIN_BID_THRESHOLD;

  /// @notice The destination address where bid tokens are forwarded after claims.
  /// @dev In ZKsync's deployment, this is a Splitter contract.
  address public destination;

  /// @notice Whether claiming is currently paused.
  bool public claimPaused;

  /// @notice Emitted when the bid threshold is updated.
  event BidThresholdSet(uint256 oldThreshold, uint256 newThreshold);

  /// @notice Emitted when the destination address is updated.
  event DestinationSet(address oldDestination, address newDestination);

  /// @notice Emitted when fee tokens are claimed.
  event Claimed(address indexed claimer, ClaimRequest[] claimRequests, uint256 bidAmount);

  /// @notice Emitted when claim pause state is changed.
  event ClaimPausedSet(bool paused);

  /// @notice Thrown when an invalid address is provided where a valid address is required.
  error FeeFlow_InvalidAddress();

  /// @notice Thrown when caller lacks the required admin role for an operation.
  error FeeFlow_Unauthorized();

  /// @notice Thrown when attempting to claim the bid token as a fee token.
  error FeeFlow_InvalidFeeToken();

  /// @notice Thrown when fee token balance is zero or below the minimum expected amount.
  error FeeFlow_InsufficientBalance();

  /// @notice Thrown when attempting to claim while paused.
  error FeeFlow_ClaimPaused();

  /// @notice Thrown when attempting to set bid threshold below minimum.
  error FeeFlow_ThresholdBelowMin();

  /// @notice Represents a fee token claim request with slippage protection.
  /// @param token The fee token to claim.
  /// @param minAmount The minimum expected balance (reverts if balance is lower).
  struct ClaimRequest {
    IERC20 token;
    uint256 minAmountRequested;
  }

  /// @param _admin The address that receives the DEFAULT_ADMIN_ROLE (governance).
  /// @param _emergencyAdmin The address that receives the EMERGENCY_ADMIN_ROLE (emergency board).
  /// @param _bidToken The token contract used for auction payments.
  /// @param _minBidThreshold The minimum threshold that can be set for bid token claims.
  /// @param _bidThreshold The initial bid threshold for claims.
  constructor(
    address _admin,
    address _emergencyAdmin,
    IERC20 _bidToken,
    uint256 _minBidThreshold,
    uint256 _bidThreshold
  ) {
    if (_admin == address(0)) revert FeeFlow_InvalidAddress();
    if (_emergencyAdmin == address(0)) revert FeeFlow_InvalidAddress();

    BID_TOKEN = _bidToken;
    MIN_BID_THRESHOLD = _minBidThreshold;
    _setBidThreshold(_bidThreshold);

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(EMERGENCY_ADMIN_ROLE, _emergencyAdmin);
  }

  /// @notice Sets the bid threshold required to claim fee assets.
  /// @param _newThreshold The new threshold amount.
  function setBidThreshold(uint256 _newThreshold) external {
    _revertIfNotAdmin();
    _setBidThreshold(_newThreshold);
  }

  /// @notice Sets the destination address where bid tokens are forwarded.
  /// @param _newDestination The new destination address.
  function setDestination(address _newDestination) external {
    _revertIfNotAdmin();
    if (_newDestination == address(0)) revert FeeFlow_InvalidAddress();
    emit DestinationSet(destination, _newDestination);
    destination = _newDestination;
  }

  /// @notice Sets the claim pause state.
  /// @param _paused Whether claiming should be paused.
  function setClaimPaused(bool _paused) external {
    _revertIfNotAdmin();
    claimPaused = _paused;
    emit ClaimPausedSet(_paused);
  }

  /// @notice Claims accumulated fee tokens in exchange for bid tokens.
  /// @dev The bid token cannot be claimed as a fee token.
  /// @param _claimRequests Array of claim requests specifying tokens and minimum amounts.
  function claim(ClaimRequest[] calldata _claimRequests) external {
    if (claimPaused) revert FeeFlow_ClaimPaused();
    uint256 _bidAmount = bidThreshold;

    BID_TOKEN.safeTransferFrom(msg.sender, destination, _bidAmount);

    for (uint256 _i = 0; _i < _claimRequests.length; _i++) {
      IERC20 _token = _claimRequests[_i].token;
      if (_token == BID_TOKEN) revert FeeFlow_InvalidFeeToken();
      uint256 _balance = _token.balanceOf(address(this));
      if (_balance == 0 || _balance < _claimRequests[_i].minAmountRequested) {
        revert FeeFlow_InsufficientBalance();
      }
      _token.safeTransfer(msg.sender, _balance);
    }

    emit Claimed(msg.sender, _claimRequests, _bidAmount);
  }

  /// @dev Reverts if the caller does not have `DEFAULT_ADMIN_ROLE` or `EMERGENCY_ADMIN_ROLE`.
  function _revertIfNotAdmin() internal view {
    if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender) && !hasRole(EMERGENCY_ADMIN_ROLE, msg.sender)) {
      revert FeeFlow_Unauthorized();
    }
  }

  /// @dev Internal helper to set bid threshold with validation and event emission.
  /// @param _newThreshold The new threshold amount.
  function _setBidThreshold(uint256 _newThreshold) internal {
    if (_newThreshold < MIN_BID_THRESHOLD) revert FeeFlow_ThresholdBelowMin();
    emit BidThresholdSet(bidThreshold, _newThreshold);
    bidThreshold = _newThreshold;
  }
}
