// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Interface for the Splitter contract.
interface ISplitter {
  /// @notice Splits the contract's token balance between burning and distributors.
  function split() external;
}
