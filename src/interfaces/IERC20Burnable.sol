// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Interface for ERC20 tokens with burn functionality.
interface IERC20Burnable is IERC20 {
  function burn(uint256 _amount) external;
}
