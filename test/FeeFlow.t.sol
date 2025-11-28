// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {FeeFlow} from "src/FeeFlow.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract FeeFlowTest is Test {
  FeeFlow internal feeFlow;

  function _assumeNonZeroAddress(address _addr) internal pure {
    vm.assume(_addr != address(0));
  }
}

contract Constructor is FeeFlowTest {
  function testFuzz_Constructor_SetsRolesAndToken(
    address _admin,
    address _emergencyAdmin,
    address _bidToken
  ) public {
    _assumeNonZeroAddress(_admin);
    _assumeNonZeroAddress(_emergencyAdmin);
    _assumeNonZeroAddress(_bidToken);

    feeFlow = new FeeFlow(_admin, _emergencyAdmin, IERC20(_bidToken));

    assertEq(address(feeFlow.BID_TOKEN()), _bidToken);
    assertTrue(feeFlow.hasRole(feeFlow.DEFAULT_ADMIN_ROLE(), _admin));
    assertTrue(feeFlow.hasRole(feeFlow.EMERGENCY_ADMIN_ROLE(), _emergencyAdmin));
  }

  function testFuzz_RevertWhen_AdminIsZeroAddress(address _emergencyAdmin, address _bidToken)
    public
  {
    _assumeNonZeroAddress(_emergencyAdmin);
    _assumeNonZeroAddress(_bidToken);

    vm.expectRevert(FeeFlow.FeeFlow_InvalidAddress.selector);
    new FeeFlow(address(0), _emergencyAdmin, IERC20(_bidToken));
  }

  function testFuzz_RevertWhen_EmergencyAdminIsZeroAddress(address _admin, address _bidToken)
    public
  {
    _assumeNonZeroAddress(_admin);
    _assumeNonZeroAddress(_bidToken);

    vm.expectRevert(FeeFlow.FeeFlow_InvalidAddress.selector);
    new FeeFlow(_admin, address(0), IERC20(_bidToken));
  }
}
