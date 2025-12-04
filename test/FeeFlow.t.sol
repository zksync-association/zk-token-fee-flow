// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {FeeFlow} from "src/FeeFlow.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract FeeFlowTest is Test {
  FeeFlow internal feeFlow;
  address internal admin;
  address internal emergencyAdmin;
  ERC20Mock internal bidToken;
  address internal destination;

  function setUp() public virtual {
    admin = makeAddr("admin");
    emergencyAdmin = makeAddr("emergencyAdmin");
    destination = makeAddr("destination");
    bidToken = new ERC20Mock();
    feeFlow = new FeeFlow(admin, emergencyAdmin, IERC20(address(bidToken)));

    vm.prank(admin);
    feeFlow.setDestination(destination);
  }

  function _assumeNonZeroAddress(address _addr) internal pure {
    vm.assume(_addr != address(0));
  }

  function _assumeNotAdmin(address _addr) internal view {
    vm.assume(_addr != admin && _addr != emergencyAdmin);
  }

  function _mintAndApproveBidToken(address _to, uint256 _amount) internal {
    bidToken.mint(_to, _amount);
    vm.prank(_to);
    bidToken.approve(address(feeFlow), _amount);
  }

  function _boundThreshold(uint256 _threshold) internal pure returns (uint256) {
    return bound(_threshold, 1, type(uint256).max);
  }

  function _boundFeeAmount(uint256 _feeAmount) internal pure returns (uint256) {
    return bound(_feeAmount, 1, type(uint128).max);
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

contract Claim is FeeFlowTest {
  function testFuzz_TransfersBidTokenToDestination(address _claimer, uint256 _threshold) public {
    // Excludes address(0): see test_RevertWhen_ClaimerIsZeroAddress
    // Excludes destination: see testFuzz_WhenClaimerIsDestination_BidTokensStayAtDestination
    vm.assume(_claimer != address(0) && _claimer != destination);
    _threshold = _boundThreshold(_threshold);

    vm.prank(admin);
    feeFlow.setBidThreshold(_threshold);

    _mintAndApproveBidToken(_claimer, _threshold);

    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](0);
    vm.prank(_claimer);
    feeFlow.claim(_claimRequests);

    assertEq(bidToken.balanceOf(destination), _threshold);
    assertEq(bidToken.balanceOf(_claimer), 0);
  }

  function testFuzz_TransfersFeeTokenToClaimer(
    address _claimer,
    uint256 _threshold,
    uint256 _feeAmount
  ) public {
    // Excludes address(0): see test_RevertWhen_ClaimerIsZeroAddress
    // Excludes address(feeFlow): see testFuzz_WhenClaimerIsFeeFlow_FeeTokensRemainInContract
    // Excludes destination: see testFuzz_WhenClaimerIsDestination_BidTokensStayAtDestination
    vm.assume(_claimer != address(0) && _claimer != address(feeFlow) && _claimer != destination);
    _threshold = _boundThreshold(_threshold);
    _feeAmount = _boundFeeAmount(_feeAmount);

    vm.prank(admin);
    feeFlow.setBidThreshold(_threshold);

    ERC20Mock _feeToken = new ERC20Mock();
    _feeToken.mint(address(feeFlow), _feeAmount);

    _mintAndApproveBidToken(_claimer, _threshold);

    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](1);
    _claimRequests[0] =
      FeeFlow.ClaimRequest({token: IERC20(address(_feeToken)), minAmountRequested: 0});
    vm.prank(_claimer);
    feeFlow.claim(_claimRequests);

    assertEq(_feeToken.balanceOf(_claimer), _feeAmount);
    assertEq(_feeToken.balanceOf(address(feeFlow)), 0);
  }

  function testFuzz_TransfersMultipleFeeTokensToClaimer(
    address _claimer,
    uint256 _threshold,
    uint256 _feeAmount1,
    uint256 _feeAmount2
  ) public {
    // Excludes address(0): see test_RevertWhen_ClaimerIsZeroAddress
    // Excludes address(feeFlow): see testFuzz_WhenClaimerIsFeeFlow_FeeTokensRemainInContract
    // Excludes destination: see testFuzz_WhenClaimerIsDestination_BidTokensStayAtDestination
    vm.assume(_claimer != address(0) && _claimer != address(feeFlow) && _claimer != destination);
    _threshold = _boundThreshold(_threshold);
    _feeAmount1 = _boundFeeAmount(_feeAmount1);
    _feeAmount2 = _boundFeeAmount(_feeAmount2);

    vm.prank(admin);
    feeFlow.setBidThreshold(_threshold);

    ERC20Mock _feeToken1 = new ERC20Mock();
    ERC20Mock _feeToken2 = new ERC20Mock();
    _feeToken1.mint(address(feeFlow), _feeAmount1);
    _feeToken2.mint(address(feeFlow), _feeAmount2);

    _mintAndApproveBidToken(_claimer, _threshold);

    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](2);
    _claimRequests[0] =
      FeeFlow.ClaimRequest({token: IERC20(address(_feeToken1)), minAmountRequested: 0});
    _claimRequests[1] =
      FeeFlow.ClaimRequest({token: IERC20(address(_feeToken2)), minAmountRequested: 0});
    vm.prank(_claimer);
    feeFlow.claim(_claimRequests);

    assertEq(_feeToken1.balanceOf(_claimer), _feeAmount1);
    assertEq(_feeToken2.balanceOf(_claimer), _feeAmount2);
  }

  function testFuzz_EmitsClaimedEvent(address _claimer, uint256 _threshold) public {
    // Excludes address(0): see test_RevertWhen_ClaimerIsZeroAddress
    // Excludes destination: see testFuzz_WhenClaimerIsDestination_BidTokensStayAtDestination
    vm.assume(_claimer != address(0) && _claimer != destination);
    _threshold = _boundThreshold(_threshold);

    vm.prank(admin);
    feeFlow.setBidThreshold(_threshold);

    _mintAndApproveBidToken(_claimer, _threshold);

    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](0);

    vm.expectEmit(address(feeFlow));
    emit FeeFlow.Claimed(_claimer, _claimRequests, _threshold);

    vm.prank(_claimer);
    feeFlow.claim(_claimRequests);
  }

  function testFuzz_WhenClaimerIsFeeFlow_FeeTokensRemainInContract(
    uint256 _threshold,
    uint256 _feeAmount
  ) public {
    _threshold = _boundThreshold(_threshold);
    _feeAmount = bound(_feeAmount, 1, type(uint256).max);

    vm.prank(admin);
    feeFlow.setBidThreshold(_threshold);

    ERC20Mock _feeToken = new ERC20Mock();
    _feeToken.mint(address(feeFlow), _feeAmount);

    bidToken.mint(address(feeFlow), _threshold);
    vm.prank(address(feeFlow));
    bidToken.approve(address(feeFlow), _threshold);

    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](1);
    _claimRequests[0] =
      FeeFlow.ClaimRequest({token: IERC20(address(_feeToken)), minAmountRequested: 0});
    vm.prank(address(feeFlow));
    feeFlow.claim(_claimRequests);

    assertEq(_feeToken.balanceOf(address(feeFlow)), _feeAmount);
  }

  function testFuzz_SucceedsWhen_BalanceAtLeastMinAmount(
    address _claimer,
    uint256 _threshold,
    uint256 _feeAmount,
    uint256 _minAmountRequested
  ) public {
    // Excludes address(0): see test_RevertWhen_ClaimerIsZeroAddress
    // Excludes address(feeFlow): see testFuzz_WhenClaimerIsFeeFlow_FeeTokensRemainInContract
    // Excludes destination: see testFuzz_WhenClaimerIsDestination_BidTokensStayAtDestination
    vm.assume(_claimer != address(0) && _claimer != address(feeFlow) && _claimer != destination);
    _threshold = _boundThreshold(_threshold);
    _feeAmount = _boundFeeAmount(_feeAmount);
    // minAmountRequested can be equal to or less than feeAmount (covers both cases)
    _minAmountRequested = bound(_minAmountRequested, 1, _feeAmount);

    vm.prank(admin);
    feeFlow.setBidThreshold(_threshold);

    ERC20Mock _feeToken = new ERC20Mock();
    _feeToken.mint(address(feeFlow), _feeAmount);

    _mintAndApproveBidToken(_claimer, _threshold);

    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](1);
    _claimRequests[0] = FeeFlow.ClaimRequest({
      token: IERC20(address(_feeToken)), minAmountRequested: _minAmountRequested
    });

    vm.prank(_claimer);
    feeFlow.claim(_claimRequests);

    assertEq(_feeToken.balanceOf(_claimer), _feeAmount);
  }

  function testFuzz_WhenClaimerIsDestination_BidTokensStayAtDestination(
    uint256 _threshold,
    uint256 _feeAmount
  ) public {
    _threshold = _boundThreshold(_threshold);
    _feeAmount = _boundFeeAmount(_feeAmount);

    vm.prank(admin);
    feeFlow.setBidThreshold(_threshold);

    ERC20Mock _feeToken = new ERC20Mock();
    _feeToken.mint(address(feeFlow), _feeAmount);

    _mintAndApproveBidToken(destination, _threshold);

    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](1);
    _claimRequests[0] =
      FeeFlow.ClaimRequest({token: IERC20(address(_feeToken)), minAmountRequested: _feeAmount});

    vm.prank(destination);
    feeFlow.claim(_claimRequests);

    // Bid tokens transferred from destination to destination (net zero change)
    assertEq(bidToken.balanceOf(destination), _threshold);
    // Fee tokens transferred to destination (the claimer)
    assertEq(_feeToken.balanceOf(destination), _feeAmount);
  }

  function testFuzz_RevertWhen_FeeTokenBalanceIsZero(address _claimer, uint256 _threshold) public {
    // Excludes address(0): see test_RevertWhen_ClaimerIsZeroAddress
    // Excludes address(feeFlow): see testFuzz_WhenClaimerIsFeeFlow_FeeTokensRemainInContract
    // Excludes destination: see testFuzz_WhenClaimerIsDestination_BidTokensStayAtDestination
    vm.assume(_claimer != address(0) && _claimer != address(feeFlow) && _claimer != destination);
    _threshold = _boundThreshold(_threshold);

    vm.prank(admin);
    feeFlow.setBidThreshold(_threshold);

    ERC20Mock _feeToken = new ERC20Mock();

    _mintAndApproveBidToken(_claimer, _threshold);

    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](1);
    _claimRequests[0] =
      FeeFlow.ClaimRequest({token: IERC20(address(_feeToken)), minAmountRequested: 0});

    vm.prank(_claimer);
    vm.expectRevert(FeeFlow.FeeFlow_InsufficientBalance.selector);
    feeFlow.claim(_claimRequests);
  }

  function testFuzz_RevertWhen_FeeTokenIsBidToken(address _claimer, uint256 _threshold) public {
    // Excludes address(0): see test_RevertWhen_ClaimerIsZeroAddress
    // Excludes destination: see testFuzz_WhenClaimerIsDestination_BidTokensStayAtDestination
    vm.assume(_claimer != address(0) && _claimer != destination);
    _threshold = _boundThreshold(_threshold);

    vm.prank(admin);
    feeFlow.setBidThreshold(_threshold);

    _mintAndApproveBidToken(_claimer, _threshold);

    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](1);
    _claimRequests[0] =
      FeeFlow.ClaimRequest({token: IERC20(address(bidToken)), minAmountRequested: 0});

    vm.prank(_claimer);
    vm.expectRevert(FeeFlow.FeeFlow_InvalidFeeToken.selector);
    feeFlow.claim(_claimRequests);
  }

  function testFuzz_RevertWhen_BalanceBelowMinAmount(
    address _claimer,
    uint256 _threshold,
    uint256 _feeAmount,
    uint256 _minAmount
  ) public {
    // Excludes address(0): see test_RevertWhen_ClaimerIsZeroAddress
    // Excludes address(feeFlow): see testFuzz_WhenClaimerIsFeeFlow_FeeTokensRemainInContract
    // Excludes destination: see testFuzz_WhenClaimerIsDestination_BidTokensStayAtDestination
    vm.assume(_claimer != address(0) && _claimer != address(feeFlow) && _claimer != destination);
    _threshold = _boundThreshold(_threshold);
    _feeAmount = bound(_feeAmount, 0, type(uint128).max);
    _minAmount = bound(_minAmount, _feeAmount + 1, type(uint256).max);

    vm.prank(admin);
    feeFlow.setBidThreshold(_threshold);

    ERC20Mock _feeToken = new ERC20Mock();
    _feeToken.mint(address(feeFlow), _feeAmount);

    _mintAndApproveBidToken(_claimer, _threshold);

    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](1);
    _claimRequests[0] =
      FeeFlow.ClaimRequest({token: IERC20(address(_feeToken)), minAmountRequested: _minAmount});

    vm.prank(_claimer);
    vm.expectRevert(FeeFlow.FeeFlow_InsufficientBalance.selector);
    feeFlow.claim(_claimRequests);
  }

  function test_RevertWhen_ClaimerIsZeroAddress(uint256 _threshold) public {
    _threshold = _boundThreshold(_threshold);

    vm.prank(admin);
    feeFlow.setBidThreshold(_threshold);

    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](0);

    // address(0) has no balance, so safeTransferFrom will revert
    vm.prank(address(0));
    vm.expectRevert();
    feeFlow.claim(_claimRequests);
  }
}
