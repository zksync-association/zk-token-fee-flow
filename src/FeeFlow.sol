// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title FeeFlow
/// @author ScopeLift
/// @notice A contract where bid token is exchanged for accumulated fee assets via a fixed-price
/// auction. As fees accumulate, it will make economic sense for a bidder to bid once the value of
/// the accrued assets exceeds the fixed bid token value. The bid token received is forwarded to a
/// Splitter contract. @custom:security-contact security@matterlabs.dev
contract FeeFlow is AccessControl {
  /// @notice Role identifier for emergency admin who can pause the contract without governance
  /// delay.
  bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN_ROLE");

  /// @notice The token used for bidding in the fee auction.
  IERC20 public immutable BID_TOKEN;

  /// @notice Thrown when an invalid address is provided where a valid address is required.
  error FeeFlow_InvalidAddress();

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
}
