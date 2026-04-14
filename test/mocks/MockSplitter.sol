// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ISplitter} from "src/interfaces/ISplitter.sol";

/// @dev Mock Splitter that tracks split() calls for testing.
contract MockSplitter is ISplitter {
  uint256 public splitCallCount;

  function split() external override {
    splitCallCount++;
  }
}
