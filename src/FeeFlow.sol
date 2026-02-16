// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
  AccessControlUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {
  UUPSUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title FeeFlow
/// @author ScopeLift
/// @notice A contract where bid tokens are exchanged for accumulated fee assets via a fixed-price
/// auction. As fees accumulate, it will make economic sense for a bidder to bid once the value of
/// the accrued assets exceeds the fixed bid token value. The bid tokens received are forwarded to a
/// destination address.
/// @dev In ZKsync's deployment, the bid token is ZK and the destination is a Splitter contract.
/// @custom:security-contact security@matterlabs.dev
contract FeeFlow is AccessControlUpgradeable, UUPSUpgradeable {
  using SafeERC20 for IERC20;

  /// @notice Role identifier for emergency admin who can pause the contract without governance
  /// delay.
  bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN_ROLE");

  /// @notice Emitted when the bid threshold is updated.
  event BidThresholdSet(uint256 oldThreshold, uint256 newThreshold);

  /// @notice Emitted when the destination address is updated.
  event DestinationSet(address oldDestination, address newDestination);

  /// @notice Emitted when fee tokens are claimed.
  event Claimed(address indexed claimer, ClaimRequest[] claimRequests, uint256 bidAmount);

  /// @notice Emitted when claim pause state is changed.
  event ClaimPausedSet(bool paused);

  /// @notice Emitted when tokens are recovered by admin.
  event Recovered(IERC20 indexed token, address indexed to, uint256 amount);

  /// @notice Emitted when a token's claimable status is changed.
  event ClaimableTokenSet(IERC20 indexed token, bool claimable);

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

  /// @notice Thrown when attempting to claim a token that is not on the whitelist.
  error FeeFlow_TokenNotClaimable();

  /// @notice Represents a fee token claim request with slippage protection.
  /// @param token The fee token to claim.
  /// @param minAmountRequested The minimum expected balance (reverts if balance is lower).
  struct ClaimRequest {
    IERC20 token;
    uint256 minAmountRequested;
  }

  /// @custom:storage-location erc7201:storage.FeeFlow
  struct FeeFlowStorage {
    IERC20 _bidToken;
    uint256 _bidThreshold;
    uint256 _minBidThreshold;
    address _destination;
    bool _claimPaused;
    mapping(IERC20 token => bool claimable) _claimableTokens;
  }

  // keccak256(abi.encode(uint256(keccak256("storage.FeeFlow")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 public constant FEEFLOW_STORAGE_LOCATION =
    0x00715c6cf755e7a595b437f0ca7683c1e81859c9ea75d4466f02abdb80ef8900;

  function _getFeeFlowStorage() private pure returns (FeeFlowStorage storage $) {
    assembly {
      $.slot := FEEFLOW_STORAGE_LOCATION
    }
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes the FeeFlow contract.
  /// @param _admin The address that can update settings and authorize upgrades.
  /// @param _emergencyAdmin The address that can update settings in emergencies.
  /// @param _bidToken The token contract used for auction payments.
  /// @param _minBidThreshold The minimum threshold that can be set for bid token claims.
  /// @param _bidThreshold The initial bid threshold for claims.
  /// @param _destination The destination address where bid tokens are forwarded.
  /// @param _claimableTokens The initial list of tokens that can be claimed.
  function initialize(
    address _admin,
    address _emergencyAdmin,
    IERC20 _bidToken,
    uint256 _minBidThreshold,
    uint256 _bidThreshold,
    address _destination,
    IERC20[] calldata _claimableTokens
  ) public initializer {
    if (_admin == address(0)) revert FeeFlow_InvalidAddress();
    if (_emergencyAdmin == address(0)) revert FeeFlow_InvalidAddress();
    if (_destination == address(0)) revert FeeFlow_InvalidAddress();
    if (_bidThreshold < _minBidThreshold) revert FeeFlow_ThresholdBelowMin();

    __AccessControl_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(EMERGENCY_ADMIN_ROLE, _emergencyAdmin);

    FeeFlowStorage storage $ = _getFeeFlowStorage();
    $._bidToken = _bidToken;
    $._minBidThreshold = _minBidThreshold;
    _setBidThreshold(_bidThreshold);
    _setDestination(_destination);

    for (uint256 _i = 0; _i < _claimableTokens.length; _i++) {
      _setClaimableToken(_claimableTokens[_i], true);
    }
  }

  /// @notice Returns the token used for bidding in the fee auction.
  function bidToken() external view returns (IERC20) {
    FeeFlowStorage storage $ = _getFeeFlowStorage();
    return $._bidToken;
  }

  /// @notice Returns the amount of bid tokens required to claim accumulated fee assets.
  function bidThreshold() external view returns (uint256) {
    FeeFlowStorage storage $ = _getFeeFlowStorage();
    return $._bidThreshold;
  }

  /// @notice Returns the minimum threshold that can be set for bid token claims.
  function minBidThreshold() external view returns (uint256) {
    FeeFlowStorage storage $ = _getFeeFlowStorage();
    return $._minBidThreshold;
  }

  /// @notice Returns the destination address where bid tokens are forwarded after claims.
  function destination() external view returns (address) {
    FeeFlowStorage storage $ = _getFeeFlowStorage();
    return $._destination;
  }

  /// @notice Returns whether claiming is currently paused.
  function claimPaused() external view returns (bool) {
    FeeFlowStorage storage $ = _getFeeFlowStorage();
    return $._claimPaused;
  }

  /// @notice Returns whether a token is claimable.
  /// @param _token The token to check claimability.
  function isClaimableToken(IERC20 _token) external view returns (bool) {
    FeeFlowStorage storage $ = _getFeeFlowStorage();
    return $._claimableTokens[_token];
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
    _setDestination(_newDestination);
  }

  /// @notice Sets the claim pause state.
  /// @param _paused Whether claiming should be paused.
  function setClaimPaused(bool _paused) external {
    _revertIfNotAdmin();
    FeeFlowStorage storage $ = _getFeeFlowStorage();
    $._claimPaused = _paused;
    emit ClaimPausedSet(_paused);
  }

  /// @notice Sets whether a token is claimable.
  /// @param _token The token to set claimability.
  /// @param _claimable Whether the token should be claimable.
  function setClaimableToken(IERC20 _token, bool _claimable) external {
    _revertIfNotAdmin();
    _setClaimableToken(_token, _claimable);
  }

  /// @notice Claims accumulated fee tokens in exchange for bid tokens.
  /// @dev The bid token cannot be claimed as a fee token.
  /// @param _claimRequests Array of claim requests specifying tokens and minimum amounts.
  function claim(ClaimRequest[] calldata _claimRequests) external {
    FeeFlowStorage storage $ = _getFeeFlowStorage();
    if ($._claimPaused) revert FeeFlow_ClaimPaused();
    uint256 _bidAmount = $._bidThreshold;

    $._bidToken.safeTransferFrom(msg.sender, $._destination, _bidAmount);

    for (uint256 _i = 0; _i < _claimRequests.length; _i++) {
      IERC20 _token = _claimRequests[_i].token;
      if (_token == $._bidToken) revert FeeFlow_InvalidFeeToken();
      if (!$._claimableTokens[_token]) revert FeeFlow_TokenNotClaimable();
      uint256 _balance = _token.balanceOf(address(this));
      if (_balance == 0 || _balance < _claimRequests[_i].minAmountRequested) {
        revert FeeFlow_InsufficientBalance();
      }
      _token.safeTransfer(msg.sender, _balance);
    }

    emit Claimed(msg.sender, _claimRequests, _bidAmount);
  }

  /// @notice Recovers tokens from the contract to an arbitrary address.
  /// @dev Only callable by the default admin.
  /// @param _token The token to recover.
  /// @param _to The address to send the tokens to.
  /// @param _amount The amount of tokens to recover.
  function recover(IERC20 _token, address _to, uint256 _amount) external {
    _revertIfNotDefaultAdmin();
    _token.safeTransfer(_to, _amount);
    emit Recovered(_token, _to, _amount);
  }

  /// @dev Authorizes an upgrade to a new implementation.
  /// @dev Only the admin can authorize upgrades.
  function _authorizeUpgrade(address) internal view override {
    _revertIfNotDefaultAdmin();
  }

  /// @dev Reverts if the caller is not the admin or emergency admin.
  function _revertIfNotAdmin() internal view {
    if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender) && !hasRole(EMERGENCY_ADMIN_ROLE, msg.sender)) {
      revert FeeFlow_Unauthorized();
    }
  }

  /// @dev Reverts if the caller is not the admin.
  function _revertIfNotDefaultAdmin() internal view {
    if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert FeeFlow_Unauthorized();
  }

  /// @dev Internal helper to set bid threshold and emit event.
  function _setBidThreshold(uint256 _newThreshold) internal {
    FeeFlowStorage storage $ = _getFeeFlowStorage();
    if (_newThreshold < $._minBidThreshold) revert FeeFlow_ThresholdBelowMin();
    emit BidThresholdSet($._bidThreshold, _newThreshold);
    $._bidThreshold = _newThreshold;
  }

  /// @dev Internal helper to set destination and emit event.
  function _setDestination(address _newDestination) internal {
    if (_newDestination == address(0)) revert FeeFlow_InvalidAddress();
    FeeFlowStorage storage $ = _getFeeFlowStorage();
    emit DestinationSet($._destination, _newDestination);
    $._destination = _newDestination;
  }

  /// @dev Sets whether a token is claimable and emits an event.
  /// @param _token The token to set claimability.
  /// @param _claimable Whether the token should be claimable.
  function _setClaimableToken(IERC20 _token, bool _claimable) internal {
    FeeFlowStorage storage $ = _getFeeFlowStorage();
    $._claimableTokens[_token] = _claimable;
    emit ClaimableTokenSet(_token, _claimable);
  }
}
