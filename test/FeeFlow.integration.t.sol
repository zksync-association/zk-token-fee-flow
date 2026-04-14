// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {FeeFlow} from "src/FeeFlow.sol";
import {Splitter} from "src/Splitter.sol";
import {IERC20Burnable} from "src/interfaces/IERC20Burnable.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20BurnableMock} from "test/mocks/ERC20BurnableMock.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

/// @title FeeFlow Integration Tests
/// @notice Tests for FeeFlow and Splitter working together.
/// @dev These tests use mock tokens to verify the full integration flow.
contract FeeFlowIntegrationTest is Test {
  FeeFlow internal feeFlow;
  Splitter internal splitter;
  ERC20BurnableMock internal bidToken;
  ERC20Mock internal feeToken;

  address internal admin;
  address internal emergencyAdmin;
  address internal distributor1;
  address internal distributor2;
  address internal claimer;

  uint256 internal constant MIN_BID_THRESHOLD = 100;
  uint256 internal constant BID_THRESHOLD = 1000 ether;

  function setUp() public {
    admin = makeAddr("admin");
    emergencyAdmin = makeAddr("emergencyAdmin");
    distributor1 = makeAddr("distributor1");
    distributor2 = makeAddr("distributor2");
    claimer = makeAddr("claimer");

    // Deploy bid token (ZK token equivalent)
    bidToken = new ERC20BurnableMock();

    // Deploy fee token
    feeToken = new ERC20Mock("Fee Token", "FEE");

    // Deploy Splitter with 50% burn and two distributors with equal weights
    Splitter.DistributorConfig[] memory _distributors = new Splitter.DistributorConfig[](2);
    _distributors[0] = Splitter.DistributorConfig({recipient: distributor1, weight: 50});
    _distributors[1] = Splitter.DistributorConfig({recipient: distributor2, weight: 50});

    Splitter _splitterImpl = new Splitter();
    ERC1967Proxy _splitterProxy = new ERC1967Proxy(
      address(_splitterImpl),
      abi.encodeCall(
        Splitter.initialize,
        (admin, emergencyAdmin, IERC20Burnable(address(bidToken)), 5000, _distributors)
      )
    );
    splitter = Splitter(address(_splitterProxy));

    // Deploy FeeFlow with Splitter as destination
    IERC20[] memory _claimableTokens = new IERC20[](1);
    _claimableTokens[0] = IERC20(address(feeToken));

    FeeFlow _feeFlowImpl = new FeeFlow();
    ERC1967Proxy _feeFlowProxy = new ERC1967Proxy(
      address(_feeFlowImpl),
      abi.encodeCall(
        FeeFlow.initialize,
        (
          admin,
          emergencyAdmin,
          IERC20(address(bidToken)),
          MIN_BID_THRESHOLD,
          BID_THRESHOLD,
          address(splitter),
          _claimableTokens
        )
      )
    );
    feeFlow = FeeFlow(address(_feeFlowProxy));
  }

  function test_FullFlow_ClaimTriggersSplitAndDistribution() public {
    // Mint fee tokens to FeeFlow
    uint256 _feeAmount = 500 ether;
    feeToken.mint(address(feeFlow), _feeAmount);

    // Mint and approve bid tokens for claimer
    bidToken.mint(claimer, BID_THRESHOLD);
    vm.prank(claimer);
    bidToken.approve(address(feeFlow), BID_THRESHOLD);

    // Record initial state
    uint256 _bidTokenSupplyBefore = bidToken.totalSupply();

    // Claimer claims fee tokens
    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](1);
    _claimRequests[0] =
      FeeFlow.ClaimRequest({token: IERC20(address(feeToken)), minAmountRequested: _feeAmount});

    vm.prank(claimer);
    feeFlow.claim(_claimRequests);

    // Verify fee tokens went to claimer
    assertEq(feeToken.balanceOf(claimer), _feeAmount);
    assertEq(feeToken.balanceOf(address(feeFlow)), 0);

    // Verify bid tokens were split: 50% burned, 50% distributed
    uint256 _expectedBurn = BID_THRESHOLD / 2;
    uint256 _expectedPerDistributor = BID_THRESHOLD / 4; // 25% each

    // Total supply decreased by burn amount
    assertEq(bidToken.totalSupply(), _bidTokenSupplyBefore - _expectedBurn);

    // Distributors received their shares
    assertEq(bidToken.balanceOf(distributor1), _expectedPerDistributor);
    assertEq(bidToken.balanceOf(distributor2), _expectedPerDistributor);

    // Splitter has zero balance
    assertEq(bidToken.balanceOf(address(splitter)), 0);

    // Claimer has zero bid tokens left
    assertEq(bidToken.balanceOf(claimer), 0);
  }

  function test_FullFlow_OneHundredPercentBurn() public {
    // Reconfigure splitter to 100% burn (no distributors)
    Splitter.DistributorConfig[] memory _emptyDistributors = new Splitter.DistributorConfig[](0);
    vm.prank(admin);
    splitter.setDistributors(_emptyDistributors);

    // Mint fee tokens to FeeFlow
    uint256 _feeAmount = 500 ether;
    feeToken.mint(address(feeFlow), _feeAmount);

    // Mint and approve bid tokens for claimer
    bidToken.mint(claimer, BID_THRESHOLD);
    vm.prank(claimer);
    bidToken.approve(address(feeFlow), BID_THRESHOLD);

    uint256 _bidTokenSupplyBefore = bidToken.totalSupply();

    // Claimer claims fee tokens
    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](1);
    _claimRequests[0] =
      FeeFlow.ClaimRequest({token: IERC20(address(feeToken)), minAmountRequested: _feeAmount});

    vm.prank(claimer);
    feeFlow.claim(_claimRequests);

    // All bid tokens burned
    assertEq(bidToken.totalSupply(), _bidTokenSupplyBefore - BID_THRESHOLD);
    assertEq(bidToken.balanceOf(address(splitter)), 0);
  }

  function test_FullFlow_ZeroPercentBurn() public {
    // Reconfigure splitter to 0% burn (all to distributors)
    vm.prank(admin);
    splitter.setBurnPercentage(0);

    // Mint fee tokens to FeeFlow
    uint256 _feeAmount = 500 ether;
    feeToken.mint(address(feeFlow), _feeAmount);

    // Mint and approve bid tokens for claimer
    bidToken.mint(claimer, BID_THRESHOLD);
    vm.prank(claimer);
    bidToken.approve(address(feeFlow), BID_THRESHOLD);

    uint256 _bidTokenSupplyBefore = bidToken.totalSupply();

    // Claimer claims fee tokens
    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](1);
    _claimRequests[0] =
      FeeFlow.ClaimRequest({token: IERC20(address(feeToken)), minAmountRequested: _feeAmount});

    vm.prank(claimer);
    feeFlow.claim(_claimRequests);

    // No burn, all distributed
    assertEq(bidToken.totalSupply(), _bidTokenSupplyBefore);
    assertEq(bidToken.balanceOf(distributor1), BID_THRESHOLD / 2);
    assertEq(bidToken.balanceOf(distributor2), BID_THRESHOLD / 2);
    assertEq(bidToken.balanceOf(address(splitter)), 0);
  }

  function testFuzz_FullFlow_VariableBurnAndWeights(
    uint256 _burnBps,
    uint256 _weight1,
    uint256 _weight2,
    uint256 _feeAmount
  ) public {
    _burnBps = bound(_burnBps, 0, 10_000);
    _weight1 = bound(_weight1, 1, type(uint96).max / 2);
    _weight2 = bound(_weight2, 1, type(uint96).max / 2);
    _feeAmount = bound(_feeAmount, 1, type(uint128).max);

    // Reconfigure splitter
    Splitter.DistributorConfig[] memory _distributors = new Splitter.DistributorConfig[](2);
    _distributors[0] =
      Splitter.DistributorConfig({recipient: distributor1, weight: uint96(_weight1)});
    _distributors[1] =
      Splitter.DistributorConfig({recipient: distributor2, weight: uint96(_weight2)});
    vm.prank(admin);
    splitter.setDistributors(_distributors);
    vm.prank(admin);
    splitter.setBurnPercentage(_burnBps);

    // Mint fee tokens to FeeFlow
    feeToken.mint(address(feeFlow), _feeAmount);

    // Mint and approve bid tokens for claimer
    bidToken.mint(claimer, BID_THRESHOLD);
    vm.prank(claimer);
    bidToken.approve(address(feeFlow), BID_THRESHOLD);

    uint256 _bidTokenSupplyBefore = bidToken.totalSupply();

    // Claimer claims fee tokens
    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](1);
    _claimRequests[0] =
      FeeFlow.ClaimRequest({token: IERC20(address(feeToken)), minAmountRequested: _feeAmount});

    vm.prank(claimer);
    feeFlow.claim(_claimRequests);

    // Calculate expected distribution
    uint256 _burnAmount = (BID_THRESHOLD * _burnBps) / 10_000;
    uint256 _distributeAmount = BID_THRESHOLD - _burnAmount;
    uint256 _totalWeight = _weight1 + _weight2;
    uint256 _expectedShare1 = (_distributeAmount * _weight1) / _totalWeight;
    uint256 _expectedShare2 = (_distributeAmount * _weight2) / _totalWeight;
    uint256 _dust = _distributeAmount - _expectedShare1 - _expectedShare2;
    uint256 _totalBurned = _burnAmount + _dust;

    // Verify
    assertEq(feeToken.balanceOf(claimer), _feeAmount);
    assertEq(bidToken.totalSupply(), _bidTokenSupplyBefore - _totalBurned);
    assertEq(bidToken.balanceOf(distributor1), _expectedShare1);
    assertEq(bidToken.balanceOf(distributor2), _expectedShare2);
    assertEq(bidToken.balanceOf(address(splitter)), 0);
  }

  function test_FullFlow_MultipleClaims() public {
    // First claim
    feeToken.mint(address(feeFlow), 500 ether);
    bidToken.mint(claimer, BID_THRESHOLD);
    vm.prank(claimer);
    bidToken.approve(address(feeFlow), BID_THRESHOLD);

    FeeFlow.ClaimRequest[] memory _claimRequests = new FeeFlow.ClaimRequest[](1);
    _claimRequests[0] =
      FeeFlow.ClaimRequest({token: IERC20(address(feeToken)), minAmountRequested: 500 ether});

    vm.prank(claimer);
    feeFlow.claim(_claimRequests);

    uint256 _dist1AfterFirst = bidToken.balanceOf(distributor1);
    uint256 _dist2AfterFirst = bidToken.balanceOf(distributor2);

    // Second claim
    feeToken.mint(address(feeFlow), 300 ether);
    bidToken.mint(claimer, BID_THRESHOLD);
    vm.prank(claimer);
    bidToken.approve(address(feeFlow), BID_THRESHOLD);

    _claimRequests[0] =
      FeeFlow.ClaimRequest({token: IERC20(address(feeToken)), minAmountRequested: 300 ether});

    vm.prank(claimer);
    feeFlow.claim(_claimRequests);

    // Distributors should have accumulated from both claims
    assertEq(bidToken.balanceOf(distributor1), _dist1AfterFirst * 2);
    assertEq(bidToken.balanceOf(distributor2), _dist2AfterFirst * 2);
    assertEq(bidToken.balanceOf(address(splitter)), 0);
  }
}
