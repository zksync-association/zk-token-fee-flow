// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract ERC20BurnableMock is ERC20 {
  constructor() ERC20("Mock Token", "MOCK") {}

  function mint(address _to, uint256 _amount) external {
    _mint(_to, _amount);
  }

  function burn(uint256 _amount) external {
    _burn(msg.sender, _amount);
  }
}
