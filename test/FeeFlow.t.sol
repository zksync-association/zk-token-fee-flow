// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {FeeFlow} from "src/FeeFlow.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract FeeFlowTest is Test {
  FeeFlow internal feeFlow;
  address internal admin;
  address internal emergencyAdmin;
  address internal zkToken;

  function setUp() public virtual {
    admin = makeAddr("admin");
    emergencyAdmin = makeAddr("emergencyAdmin");
    zkToken = makeAddr("zkToken");
    feeFlow = new FeeFlow(admin, emergencyAdmin, IERC20(zkToken));
  }

  function _assumeNonZeroAddress(address _addr) internal pure {
    vm.assume(_addr != address(0));
  }

  function _assumeNotAdmin(address _addr) internal view {
    vm.assume(_addr != admin && _addr != emergencyAdmin);
  }
}

contract Constructor is FeeFlowTest {
  function setUp() public override {}

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

contract SetBidThreshold is FeeFlowTest {
  function testFuzz_SetsThreshold_WhenCalledByDefaultAdmin(uint256 _newThreshold) public {
    vm.prank(admin);
    feeFlow.setBidThreshold(_newThreshold);

    assertEq(feeFlow.bidThreshold(), _newThreshold);
  }

  function testFuzz_SetsThreshold_WhenCalledByEmergencyAdmin(uint256 _newThreshold) public {
    vm.prank(emergencyAdmin);
    feeFlow.setBidThreshold(_newThreshold);

    assertEq(feeFlow.bidThreshold(), _newThreshold);
  }

  function testFuzz_EmitsEvent_WhenThresholdIsSet(uint256 _oldThreshold, uint256 _newThreshold)
    public
  {
    vm.prank(admin);
    feeFlow.setBidThreshold(_oldThreshold);

    vm.expectEmit(address(feeFlow));
    emit FeeFlow.BidThresholdSet(_oldThreshold, _newThreshold);

    vm.prank(admin);
    feeFlow.setBidThreshold(_newThreshold);
  }

  function testFuzz_RevertWhen_CallerIsNotAdmin(address _caller, uint256 _newThreshold) public {
    _assumeNotAdmin(_caller);

    vm.prank(_caller);
    vm.expectRevert(FeeFlow.FeeFlow_Unauthorized.selector);
    feeFlow.setBidThreshold(_newThreshold);
  }
}

contract SetDestination is FeeFlowTest {
  function testFuzz_SetsDestination_WhenCalledByDefaultAdmin(address _newDestination) public {
    vm.assume(_newDestination != address(0));

    vm.prank(admin);
    feeFlow.setDestination(_newDestination);

    assertEq(feeFlow.destination(), _newDestination);
  }

  function testFuzz_SetsDestination_WhenCalledByEmergencyAdmin(address _newDestination) public {
    vm.assume(_newDestination != address(0));

    vm.prank(emergencyAdmin);
    feeFlow.setDestination(_newDestination);

    assertEq(feeFlow.destination(), _newDestination);
  }

  function testFuzz_EmitsEvent_WhenDestinationIsSet(
    address _oldDestination,
    address _newDestination
  ) public {
    vm.assume(_oldDestination != address(0));
    vm.assume(_newDestination != address(0));

    vm.prank(admin);
    feeFlow.setDestination(_oldDestination);

    vm.expectEmit(address(feeFlow));
    emit FeeFlow.DestinationSet(_oldDestination, _newDestination);

    vm.prank(admin);
    feeFlow.setDestination(_newDestination);
  }

  function testFuzz_RevertWhen_CallerIsNotAdmin(address _caller, address _newDestination) public {
    vm.assume(_newDestination != address(0));
    _assumeNotAdmin(_caller);

    vm.prank(_caller);
    vm.expectRevert(FeeFlow.FeeFlow_Unauthorized.selector);
    feeFlow.setDestination(_newDestination);
  }

  function test_RevertWhen_DestinationIsZero() public {
    vm.prank(admin);
    vm.expectRevert(FeeFlow.FeeFlow_InvalidAddress.selector);
    feeFlow.setDestination(address(0));
  }
}
