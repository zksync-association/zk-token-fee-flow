// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {FeeFlow} from "src/FeeFlow.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {
  Initializable
} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract FeeFlowTest is Test {
  FeeFlow internal feeFlow;
  address internal admin;
  address internal emergencyAdmin;
  ERC20Mock internal bidToken;
  address internal destination;
  uint256 internal minBidThreshold = 100;
  uint256 internal initialBidThreshold = 1000;

  function _deployFeeFlow(
    address _admin,
    address _emergencyAdmin,
    IERC20 _bidToken,
    uint256 _minBidThreshold,
    uint256 _bidThreshold,
    address _destination,
    IERC20[] memory _claimableTokens
  ) internal returns (FeeFlow) {
    FeeFlow _implementation = new FeeFlow();
    ERC1967Proxy _proxy = new ERC1967Proxy(
      address(_implementation),
      abi.encodeCall(
        FeeFlow.initialize,
        (
          _admin,
          _emergencyAdmin,
          _bidToken,
          _minBidThreshold,
          _bidThreshold,
          _destination,
          _claimableTokens
        )
      )
    );
    return FeeFlow(address(_proxy));
  }

  function setUp() public virtual {
    admin = makeAddr("admin");
    emergencyAdmin = makeAddr("emergencyAdmin");
    destination = makeAddr("destination");
    bidToken = new ERC20Mock();
    IERC20[] memory _claimableTokens = new IERC20[](0);
    feeFlow = _deployFeeFlow(
      admin,
      emergencyAdmin,
      IERC20(address(bidToken)),
      minBidThreshold,
      initialBidThreshold,
      destination,
      _claimableTokens
    );
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

  function _boundThreshold(uint256 _threshold) internal view returns (uint256) {
    return bound(_threshold, minBidThreshold, type(uint256).max);
  }

  function _boundFeeAmount(uint256 _feeAmount) internal pure returns (uint256) {
    return bound(_feeAmount, 1, type(uint128).max);
  }

  function _whitelistToken(IERC20 _token) internal {
    vm.prank(admin);
    feeFlow.setClaimableToken(_token, true);
  }
}

contract Initialize is FeeFlowTest {
  function test_StorageLocationMatchesEIP7201() public view {
    bytes32 _expected =
      keccak256(abi.encode(uint256(keccak256("storage.FeeFlow")) - 1)) & ~bytes32(uint256(0xff));
    assertEq(feeFlow.FEEFLOW_STORAGE_LOCATION(), _expected);
  }

  function testFuzz_Initialize_SetsStateCorrectly(
    address _admin,
    address _emergencyAdmin,
    address _bidToken,
    uint256 _minBidThreshold,
    uint256 _bidThreshold,
    address _destination
  ) public {
    _assumeNonZeroAddress(_admin);
    _assumeNonZeroAddress(_emergencyAdmin);
    _assumeNonZeroAddress(_bidToken);
    _assumeNonZeroAddress(_destination);
    _bidThreshold = bound(_bidThreshold, _minBidThreshold, type(uint256).max);

    IERC20[] memory _claimableTokens = new IERC20[](0);
    feeFlow = _deployFeeFlow(
      _admin,
      _emergencyAdmin,
      IERC20(_bidToken),
      _minBidThreshold,
      _bidThreshold,
      _destination,
      _claimableTokens
    );

    assertEq(address(feeFlow.bidToken()), _bidToken);
    assertEq(feeFlow.minBidThreshold(), _minBidThreshold);
    assertEq(feeFlow.bidThreshold(), _bidThreshold);
    assertEq(feeFlow.destination(), _destination);
    assertTrue(feeFlow.hasRole(feeFlow.DEFAULT_ADMIN_ROLE(), _admin));
    assertTrue(feeFlow.hasRole(feeFlow.EMERGENCY_ADMIN_ROLE(), _emergencyAdmin));
  }

  function testFuzz_Initialize_SetsClaimableTokens(address _token1, address _token2) public {
    vm.assume(_token1 != _token2);

    IERC20[] memory _claimableTokens = new IERC20[](2);
    _claimableTokens[0] = IERC20(_token1);
    _claimableTokens[1] = IERC20(_token2);

    feeFlow = _deployFeeFlow(
      admin,
      emergencyAdmin,
      IERC20(address(bidToken)),
      minBidThreshold,
      initialBidThreshold,
      destination,
      _claimableTokens
    );

    assertTrue(feeFlow.isClaimableToken(IERC20(_token1)));
    assertTrue(feeFlow.isClaimableToken(IERC20(_token2)));
  }

  function testFuzz_RevertWhen_AdminIsZeroAddress(
    address _emergencyAdmin,
    address _bidToken,
    uint256 _minBidThreshold,
    uint256 _bidThreshold,
    address _destination
  ) public {
    _assumeNonZeroAddress(_emergencyAdmin);
    _assumeNonZeroAddress(_bidToken);
    _assumeNonZeroAddress(_destination);
    _bidThreshold = bound(_bidThreshold, _minBidThreshold, type(uint256).max);

    IERC20[] memory _claimableTokens = new IERC20[](0);
    FeeFlow _implementation = new FeeFlow();
    vm.expectRevert(FeeFlow.FeeFlow_InvalidAddress.selector);
    new ERC1967Proxy(
      address(_implementation),
      abi.encodeCall(
        FeeFlow.initialize,
        (
          address(0),
          _emergencyAdmin,
          IERC20(_bidToken),
          _minBidThreshold,
          _bidThreshold,
          _destination,
          _claimableTokens
        )
      )
    );
  }

  function testFuzz_RevertWhen_EmergencyAdminIsZeroAddress(
    address _admin,
    address _bidToken,
    uint256 _minBidThreshold,
    uint256 _bidThreshold,
    address _destination
  ) public {
    _assumeNonZeroAddress(_admin);
    _assumeNonZeroAddress(_bidToken);
    _assumeNonZeroAddress(_destination);
    _bidThreshold = bound(_bidThreshold, _minBidThreshold, type(uint256).max);

    IERC20[] memory _claimableTokens = new IERC20[](0);
    FeeFlow _implementation = new FeeFlow();
    vm.expectRevert(FeeFlow.FeeFlow_InvalidAddress.selector);
    new ERC1967Proxy(
      address(_implementation),
      abi.encodeCall(
        FeeFlow.initialize,
        (
          _admin,
          address(0),
          IERC20(_bidToken),
          _minBidThreshold,
          _bidThreshold,
          _destination,
          _claimableTokens
        )
      )
    );
  }

  function testFuzz_RevertWhen_DestinationIsZeroAddress(
    address _admin,
    address _emergencyAdmin,
    address _bidToken,
    uint256 _minBidThreshold,
    uint256 _bidThreshold
  ) public {
    _assumeNonZeroAddress(_admin);
    _assumeNonZeroAddress(_emergencyAdmin);
    _assumeNonZeroAddress(_bidToken);
    _bidThreshold = bound(_bidThreshold, _minBidThreshold, type(uint256).max);

    IERC20[] memory _claimableTokens = new IERC20[](0);
    FeeFlow _implementation = new FeeFlow();
    vm.expectRevert(FeeFlow.FeeFlow_InvalidAddress.selector);
    new ERC1967Proxy(
      address(_implementation),
      abi.encodeCall(
        FeeFlow.initialize,
        (
          _admin,
          _emergencyAdmin,
          IERC20(_bidToken),
          _minBidThreshold,
          _bidThreshold,
          address(0),
          _claimableTokens
        )
      )
    );
  }

  function testFuzz_RevertWhen_BidThresholdBelowMin(
    address _admin,
    address _emergencyAdmin,
    address _bidToken,
    uint256 _minBidThreshold,
    uint256 _bidThreshold,
    address _destination
  ) public {
    _assumeNonZeroAddress(_admin);
    _assumeNonZeroAddress(_emergencyAdmin);
    _assumeNonZeroAddress(_bidToken);
    _assumeNonZeroAddress(_destination);
    _minBidThreshold = bound(_minBidThreshold, 1, type(uint256).max);
    _bidThreshold = bound(_bidThreshold, 0, _minBidThreshold - 1);

    IERC20[] memory _claimableTokens = new IERC20[](0);
    FeeFlow _implementation = new FeeFlow();
    vm.expectRevert(FeeFlow.FeeFlow_ThresholdBelowMin.selector);
    new ERC1967Proxy(
      address(_implementation),
      abi.encodeCall(
        FeeFlow.initialize,
        (
          _admin,
          _emergencyAdmin,
          IERC20(_bidToken),
          _minBidThreshold,
          _bidThreshold,
          _destination,
          _claimableTokens
        )
      )
    );
  }

  function test_RevertWhen_InitializeCalledTwice() public {
    IERC20[] memory _claimableTokens = new IERC20[](0);
    vm.expectRevert();
    feeFlow.initialize(
      admin,
      emergencyAdmin,
      IERC20(address(bidToken)),
      minBidThreshold,
      initialBidThreshold,
      destination,
      _claimableTokens
    );
  }

  function test_RevertWhen_ImplementationInitialized() public {
    IERC20[] memory _claimableTokens = new IERC20[](0);
    FeeFlow _implementation = new FeeFlow();
    vm.expectRevert();
    _implementation.initialize(
      admin,
      emergencyAdmin,
      IERC20(address(bidToken)),
      minBidThreshold,
      initialBidThreshold,
      destination,
      _claimableTokens
    );
  }

  function test_ConstructorDisablesInitializers() public {
    // Deploy a fresh implementation (not behind a proxy)
    FeeFlow _implementation = new FeeFlow();

    IERC20[] memory _claimableTokens = new IERC20[](0);
    // The constructor calls _disableInitializers(), so any attempt to initialize should revert
    // with InvalidInitialization error from Initializable contract
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _implementation.initialize(
      admin,
      emergencyAdmin,
      IERC20(address(bidToken)),
      minBidThreshold,
      initialBidThreshold,
      destination,
      _claimableTokens
    );
  }
}

contract SetBidThreshold is FeeFlowTest {
  function testFuzz_SetsThreshold_WhenCalledByDefaultAdmin(uint256 _newThreshold) public {
    _newThreshold = _boundThreshold(_newThreshold);

    vm.prank(admin);
    feeFlow.setBidThreshold(_newThreshold);

    assertEq(feeFlow.bidThreshold(), _newThreshold);
  }

  function testFuzz_SetsThreshold_WhenCalledByEmergencyAdmin(uint256 _newThreshold) public {
    _newThreshold = _boundThreshold(_newThreshold);

    vm.prank(emergencyAdmin);
    feeFlow.setBidThreshold(_newThreshold);

    assertEq(feeFlow.bidThreshold(), _newThreshold);
  }

  function testFuzz_EmitsEvent_WhenThresholdIsSet(uint256 _oldThreshold, uint256 _newThreshold)
    public
  {
    _oldThreshold = _boundThreshold(_oldThreshold);
    _newThreshold = _boundThreshold(_newThreshold);

    vm.prank(admin);
    feeFlow.setBidThreshold(_oldThreshold);

    vm.expectEmit(address(feeFlow));
    emit FeeFlow.BidThresholdSet(_oldThreshold, _newThreshold);

    vm.prank(admin);
    feeFlow.setBidThreshold(_newThreshold);
  }

  function testFuzz_RevertWhen_CallerIsNotAdmin(address _caller, uint256 _newThreshold) public {
    _assumeNotAdmin(_caller);
    _newThreshold = _boundThreshold(_newThreshold);

    vm.prank(_caller);
    vm.expectRevert(FeeFlow.FeeFlow_Unauthorized.selector);
    feeFlow.setBidThreshold(_newThreshold);
  }

  function testFuzz_RevertWhen_ThresholdBelowMin(uint256 _newThreshold) public {
    _newThreshold = bound(_newThreshold, 0, minBidThreshold - 1);

    vm.prank(admin);
    vm.expectRevert(FeeFlow.FeeFlow_ThresholdBelowMin.selector);
    feeFlow.setBidThreshold(_newThreshold);
  }

  function testFuzz_RevertWhen_ThresholdBelowMin_EmergencyAdmin(uint256 _newThreshold) public {
    _newThreshold = bound(_newThreshold, 0, minBidThreshold - 1);

    vm.prank(emergencyAdmin);
    vm.expectRevert(FeeFlow.FeeFlow_ThresholdBelowMin.selector);
    feeFlow.setBidThreshold(_newThreshold);
  }

  function test_SucceedsWhen_ThresholdEqualsMin() public {
    vm.prank(admin);
    feeFlow.setBidThreshold(minBidThreshold);

    assertEq(feeFlow.bidThreshold(), minBidThreshold);
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

contract SetClaimPaused is FeeFlowTest {
  function testFuzz_SetsPausedState_WhenCalledByDefaultAdmin(bool _paused) public {
    vm.prank(admin);
    feeFlow.setClaimPaused(_paused);

    assertEq(feeFlow.claimPaused(), _paused);
  }

  function testFuzz_SetsPausedState_WhenCalledByEmergencyAdmin(bool _paused) public {
    vm.prank(emergencyAdmin);
    feeFlow.setClaimPaused(_paused);

    assertEq(feeFlow.claimPaused(), _paused);
  }

  function testFuzz_EmitsEvent_WhenPauseStateIsSet(bool _paused) public {
    vm.expectEmit(address(feeFlow));
    emit FeeFlow.ClaimPausedSet(_paused);

    vm.prank(admin);
    feeFlow.setClaimPaused(_paused);
  }

  function testFuzz_RevertWhen_CallerIsNotAdmin(address _caller, bool _paused) public {
    _assumeNotAdmin(_caller);

    vm.prank(_caller);
    vm.expectRevert(FeeFlow.FeeFlow_Unauthorized.selector);
    feeFlow.setClaimPaused(_paused);
  }

  function testFuzz_SetsCorrectState_ForAllTransitions(bool _initialState, bool _newState) public {
    vm.prank(admin);
    feeFlow.setClaimPaused(_initialState);
    assertEq(feeFlow.claimPaused(), _initialState);

    vm.prank(admin);
    feeFlow.setClaimPaused(_newState);
    assertEq(feeFlow.claimPaused(), _newState);
  }
}

contract SetClaimableToken is FeeFlowTest {
  function testFuzz_SetsClaimableToken_WhenCalledByDefaultAdmin(address _token, bool _claimable)
    public
  {
    vm.prank(admin);
    feeFlow.setClaimableToken(IERC20(_token), _claimable);

    assertEq(feeFlow.isClaimableToken(IERC20(_token)), _claimable);
  }

  function testFuzz_SetsClaimableToken_WhenCalledByEmergencyAdmin(address _token, bool _claimable)
    public
  {
    vm.prank(emergencyAdmin);
    feeFlow.setClaimableToken(IERC20(_token), _claimable);

    assertEq(feeFlow.isClaimableToken(IERC20(_token)), _claimable);
  }

  function testFuzz_RemovesClaimableToken(address _token) public {
    vm.prank(admin);
    feeFlow.setClaimableToken(IERC20(_token), true);
    assertTrue(feeFlow.isClaimableToken(IERC20(_token)));

    vm.prank(admin);
    feeFlow.setClaimableToken(IERC20(_token), false);
    assertFalse(feeFlow.isClaimableToken(IERC20(_token)));
  }

  function testFuzz_EmitsEvent_WhenClaimableTokenIsSet(address _token, bool _claimable) public {
    vm.expectEmit(address(feeFlow));
    emit FeeFlow.ClaimableTokenSet(IERC20(_token), _claimable);

    vm.prank(admin);
    feeFlow.setClaimableToken(IERC20(_token), _claimable);
  }

  function testFuzz_RevertWhen_CallerIsNotAdmin(address _caller, address _token) public {
    _assumeNotAdmin(_caller);

    vm.prank(_caller);
    vm.expectRevert(FeeFlow.FeeFlow_Unauthorized.selector);
    feeFlow.setClaimableToken(IERC20(_token), true);
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

    _whitelistToken(IERC20(address(_feeToken)));

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

    _whitelistToken(IERC20(address(_feeToken1)));
    _whitelistToken(IERC20(address(_feeToken2)));

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

    _whitelistToken(IERC20(address(_feeToken)));

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

    _whitelistToken(IERC20(address(_feeToken)));

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

    _whitelistToken(IERC20(address(_feeToken)));

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

    _whitelistToken(IERC20(address(_feeToken)));

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

    _whitelistToken(IERC20(address(_feeToken)));

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

  function testFuzz_RevertWhen_ClaimIsPaused(address _claimer) public {
    vm.prank(admin);
    feeFlow.setClaimPaused(true);

    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](0);

    vm.prank(_claimer);
    vm.expectRevert(FeeFlow.FeeFlow_ClaimPaused.selector);
    feeFlow.claim(_claimRequests);
  }

  function testFuzz_RevertWhen_TokenNotClaimable(
    address _claimer,
    uint256 _threshold,
    uint256 _feeAmount
  ) public {
    vm.assume(_claimer != address(0) && _claimer != address(feeFlow) && _claimer != destination);
    _threshold = _boundThreshold(_threshold);
    _feeAmount = _boundFeeAmount(_feeAmount);

    vm.prank(admin);
    feeFlow.setBidThreshold(_threshold);

    ERC20Mock _feeToken = new ERC20Mock();
    _feeToken.mint(address(feeFlow), _feeAmount);

    // Note: token is NOT whitelisted

    _mintAndApproveBidToken(_claimer, _threshold);

    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](1);
    _claimRequests[0] =
      FeeFlow.ClaimRequest({token: IERC20(address(_feeToken)), minAmountRequested: _feeAmount});

    vm.prank(_claimer);
    vm.expectRevert(FeeFlow.FeeFlow_TokenNotClaimable.selector);
    feeFlow.claim(_claimRequests);
  }
}

contract Upgrade is FeeFlowTest {
  function test_UpgradeSucceeds_WhenCalledByAdmin() public {
    FeeFlow _newImplementation = new FeeFlow();

    vm.prank(admin);
    feeFlow.upgradeToAndCall(address(_newImplementation), "");
  }

  function testFuzz_StoragePreserved_AfterUpgrade(uint256 _threshold, address _newDestination)
    public
  {
    vm.assume(_newDestination != address(0));
    _threshold = _boundThreshold(_threshold);

    vm.prank(admin);
    feeFlow.setBidThreshold(_threshold);

    vm.prank(admin);
    feeFlow.setDestination(_newDestination);

    FeeFlow _newImplementation = new FeeFlow();

    vm.prank(admin);
    feeFlow.upgradeToAndCall(address(_newImplementation), "");

    assertEq(feeFlow.bidThreshold(), _threshold);
    assertEq(feeFlow.destination(), _newDestination);
    assertEq(address(feeFlow.bidToken()), address(bidToken));
    assertTrue(feeFlow.hasRole(feeFlow.DEFAULT_ADMIN_ROLE(), admin));
    assertTrue(feeFlow.hasRole(feeFlow.EMERGENCY_ADMIN_ROLE(), emergencyAdmin));
  }

  function testFuzz_RevertWhen_UpgradeCalledByNonAdmin(address _caller) public {
    vm.assume(_caller != admin);

    FeeFlow _newImplementation = new FeeFlow();

    vm.prank(_caller);
    vm.expectRevert(FeeFlow.FeeFlow_Unauthorized.selector);
    feeFlow.upgradeToAndCall(address(_newImplementation), "");
  }

  function test_RevertWhen_UpgradeCalledByEmergencyAdmin() public {
    FeeFlow _newImplementation = new FeeFlow();

    vm.prank(emergencyAdmin);
    vm.expectRevert(FeeFlow.FeeFlow_Unauthorized.selector);
    feeFlow.upgradeToAndCall(address(_newImplementation), "");
  }
}

contract Recover is FeeFlowTest {
  function testFuzz_RecoversTokens_WhenCalledByAdmin(address _to, uint256 _amount) public {
    vm.assume(_to != address(0) && _to != address(feeFlow));

    ERC20Mock _token = new ERC20Mock();
    _token.mint(address(feeFlow), _amount);

    vm.prank(admin);
    feeFlow.recover(IERC20(address(_token)), _to, _amount);

    assertEq(_token.balanceOf(_to), _amount);
    assertEq(_token.balanceOf(address(feeFlow)), 0);
  }

  function testFuzz_EmitsEvent_WhenTokensRecovered(address _to, uint256 _amount) public {
    vm.assume(_to != address(0));

    ERC20Mock _token = new ERC20Mock();
    _token.mint(address(feeFlow), _amount);

    vm.expectEmit(address(feeFlow));
    emit FeeFlow.Recovered(IERC20(address(_token)), _to, _amount);

    vm.prank(admin);
    feeFlow.recover(IERC20(address(_token)), _to, _amount);
  }

  function testFuzz_RevertWhen_CallerIsNotAdmin(address _caller, address _to, uint256 _amount)
    public
  {
    vm.assume(_caller != admin);

    ERC20Mock _token = new ERC20Mock();
    _token.mint(address(feeFlow), _amount);

    vm.prank(_caller);
    vm.expectRevert(FeeFlow.FeeFlow_Unauthorized.selector);
    feeFlow.recover(IERC20(address(_token)), _to, _amount);
  }

  function test_RevertWhen_CallerIsEmergencyAdmin() public {
    ERC20Mock _token = new ERC20Mock();
    _token.mint(address(feeFlow), 1000);

    vm.prank(emergencyAdmin);
    vm.expectRevert(FeeFlow.FeeFlow_Unauthorized.selector);
    feeFlow.recover(IERC20(address(_token)), destination, 1000);
  }

  function testFuzz_RevertWhen_InsufficientBalance(address _to, uint256 _balance, uint256 _amount)
    public
  {
    vm.assume(_to != address(0));
    _balance = bound(_balance, 0, type(uint128).max);
    _amount = bound(_amount, _balance + 1, type(uint256).max);

    ERC20Mock _token = new ERC20Mock();
    _token.mint(address(feeFlow), _balance);

    vm.prank(admin);
    vm.expectRevert();
    feeFlow.recover(IERC20(address(_token)), _to, _amount);
  }
}
