// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Splitter} from "src/Splitter.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Burnable} from "src/interfaces/IERC20Burnable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20BurnableMock} from "test/mocks/ERC20BurnableMock.sol";

contract SplitterTest is Test {
  Splitter internal splitter;
  ERC20BurnableMock internal splitToken;
  address internal admin;
  address internal emergencyAdmin;
  uint256 internal constant DEFAULT_BURN_BPS = 10_000;
  uint256 internal constant BPS_DENOMINATOR = 10_000;

  function _deploySplitter(address _admin, address _emergencyAdmin) internal returns (Splitter) {
    Splitter.DistributorConfig[] memory _emptyDistributors = new Splitter.DistributorConfig[](0);
    return _deploySplitter(
      _admin,
      _emergencyAdmin,
      IERC20Burnable(address(splitToken)),
      DEFAULT_BURN_BPS,
      _emptyDistributors
    );
  }

  function _deploySplitter(
    address _admin,
    address _emergencyAdmin,
    IERC20Burnable _splitToken,
    uint256 _burnBps
  ) internal returns (Splitter) {
    Splitter.DistributorConfig[] memory _emptyDistributors = new Splitter.DistributorConfig[](0);
    return _deploySplitter(_admin, _emergencyAdmin, _splitToken, _burnBps, _emptyDistributors);
  }

  function _deploySplitter(
    address _admin,
    address _emergencyAdmin,
    IERC20Burnable _splitToken,
    uint256 _burnBps,
    Splitter.DistributorConfig[] memory _initialDistributors
  ) internal returns (Splitter) {
    Splitter _implementation = new Splitter();
    ERC1967Proxy _proxy = new ERC1967Proxy(
      address(_implementation),
      abi.encodeCall(
        Splitter.initialize, (_admin, _emergencyAdmin, _splitToken, _burnBps, _initialDistributors)
      )
    );
    return Splitter(address(_proxy));
  }

  function setUp() public virtual {
    admin = makeAddr("admin");
    emergencyAdmin = makeAddr("emergencyAdmin");
    splitToken = new ERC20BurnableMock();
    splitter = _deploySplitter(admin, emergencyAdmin);
  }

  function _assumeNonZeroAddress(address _addr) internal pure {
    vm.assume(_addr != address(0));
  }

  function _assumeNotAdmin(address _addr) internal view {
    vm.assume(_addr != admin && _addr != emergencyAdmin);
  }

  function _assumeNotSplitter(address _addr) internal view {
    vm.assume(_addr != address(splitter));
  }

  function _boundWeight(uint256 _weight) internal pure returns (uint256) {
    return bound(_weight, 1, type(uint96).max);
  }

  function _createDistributors(address _recipient, uint256 _weight)
    internal
    pure
    returns (Splitter.DistributorConfig[] memory)
  {
    Splitter.DistributorConfig[] memory _distributors = new Splitter.DistributorConfig[](1);
    _distributors[0] = Splitter.DistributorConfig({recipient: _recipient, weight: uint96(_weight)});
    return _distributors;
  }

  function _createDistributors(
    address _recipient1,
    uint256 _weight1,
    address _recipient2,
    uint256 _weight2
  ) internal pure returns (Splitter.DistributorConfig[] memory) {
    Splitter.DistributorConfig[] memory _distributors = new Splitter.DistributorConfig[](2);
    _distributors[0] =
      Splitter.DistributorConfig({recipient: _recipient1, weight: uint96(_weight1)});
    _distributors[1] =
      Splitter.DistributorConfig({recipient: _recipient2, weight: uint96(_weight2)});
    return _distributors;
  }

  function _setDistributors(Splitter.DistributorConfig[] memory _distributors) internal {
    vm.prank(admin);
    splitter.setDistributors(_distributors);
  }

  function _addDistributor() internal {
    address _recipient = makeAddr("recipient");
    Splitter.DistributorConfig[] memory _distributors = _createDistributors(_recipient, 100);
    _setDistributors(_distributors);
  }

  function _addDistributors(address _recipient, uint256 _weight) internal {
    Splitter.DistributorConfig[] memory _distributors = _createDistributors(_recipient, _weight);
    _setDistributors(_distributors);
  }

  function _addTwoDistributors(
    address _recipient1,
    uint256 _weight1,
    address _recipient2,
    uint256 _weight2
  ) internal {
    Splitter.DistributorConfig[] memory _distributors =
      _createDistributors(_recipient1, _weight1, _recipient2, _weight2);
    _setDistributors(_distributors);
  }

  function _setBurnBps(uint256 _burnBps) internal {
    vm.prank(admin);
    splitter.setBurnPercentage(_burnBps);
  }

  function _mintToSplitter(uint256 _amount) internal {
    splitToken.mint(address(splitter), _amount);
  }
}

contract Initialize is SplitterTest {
  function test_StorageLocationMatchesEIP7201() public view {
    bytes32 _expected =
      keccak256(abi.encode(uint256(keccak256("storage.Splitter")) - 1)) & ~bytes32(uint256(0xff));
    assertEq(splitter.SPLITTER_STORAGE_LOCATION(), _expected);
  }

  function testFuzz_Initialize_SetsStateCorrectly(address _admin, address _emergencyAdmin) public {
    _assumeNonZeroAddress(_admin);
    _assumeNonZeroAddress(_emergencyAdmin);

    splitter = _deploySplitter(
      _admin, _emergencyAdmin, IERC20Burnable(address(splitToken)), DEFAULT_BURN_BPS
    );

    assertTrue(splitter.hasRole(splitter.DEFAULT_ADMIN_ROLE(), _admin));
    assertTrue(splitter.hasRole(splitter.EMERGENCY_ADMIN_ROLE(), _emergencyAdmin));
    assertEq(address(splitter.splitToken()), address(splitToken));
    assertEq(splitter.burnPercentage(), DEFAULT_BURN_BPS);
    assertEq(splitter.distributedPercentage(), 0);
    assertEq(splitter.totalDistributorWeight(), 0);
    assertEq(splitter.distributors().length, 0);
  }

  function testFuzz_Initialize_SetsInitialDistributors(
    address _admin,
    address _emergencyAdmin,
    address _recipient,
    uint256 _weight,
    uint256 _burnBps
  ) public {
    _assumeNonZeroAddress(_admin);
    _assumeNonZeroAddress(_emergencyAdmin);
    _assumeNonZeroAddress(_recipient);
    _weight = _boundWeight(_weight);
    _burnBps = bound(_burnBps, 0, DEFAULT_BURN_BPS);

    Splitter.DistributorConfig[] memory _distributors = _createDistributors(_recipient, _weight);
    splitter = _deploySplitter(
      _admin, _emergencyAdmin, IERC20Burnable(address(splitToken)), _burnBps, _distributors
    );

    Splitter.DistributorConfig[] memory _result = splitter.distributors();
    assertEq(_result.length, 1);
    assertEq(_result[0].recipient, _recipient);
    assertEq(_result[0].weight, _weight);
    assertEq(splitter.totalDistributorWeight(), _weight);
    assertEq(splitter.burnPercentage(), _burnBps);
  }

  function testFuzz_RevertWhen_AdminIsZeroAddress(address _emergencyAdmin) public {
    _assumeNonZeroAddress(_emergencyAdmin);

    Splitter.DistributorConfig[] memory _emptyDistributors = new Splitter.DistributorConfig[](0);
    Splitter _implementation = new Splitter();
    vm.expectRevert(Splitter.Splitter_InvalidAddress.selector);
    new ERC1967Proxy(
      address(_implementation),
      abi.encodeCall(
        Splitter.initialize,
        (
          address(0),
          _emergencyAdmin,
          IERC20Burnable(address(splitToken)),
          DEFAULT_BURN_BPS,
          _emptyDistributors
        )
      )
    );
  }

  function testFuzz_RevertWhen_EmergencyAdminIsZeroAddress(address _admin) public {
    _assumeNonZeroAddress(_admin);

    Splitter.DistributorConfig[] memory _emptyDistributors = new Splitter.DistributorConfig[](0);
    Splitter _implementation = new Splitter();
    vm.expectRevert(Splitter.Splitter_InvalidAddress.selector);
    new ERC1967Proxy(
      address(_implementation),
      abi.encodeCall(
        Splitter.initialize,
        (
          _admin,
          address(0),
          IERC20Burnable(address(splitToken)),
          DEFAULT_BURN_BPS,
          _emptyDistributors
        )
      )
    );
  }

  function testFuzz_RevertWhen_InitialDistributorRecipientIsZeroAddress(
    address _admin,
    address _emergencyAdmin,
    uint256 _weight
  ) public {
    _assumeNonZeroAddress(_admin);
    _assumeNonZeroAddress(_emergencyAdmin);
    _weight = _boundWeight(_weight);

    Splitter.DistributorConfig[] memory _distributors = _createDistributors(address(0), _weight);
    Splitter _implementation = new Splitter();
    vm.expectRevert(Splitter.Splitter_InvalidAddress.selector);
    new ERC1967Proxy(
      address(_implementation),
      abi.encodeCall(
        Splitter.initialize,
        (
          _admin,
          _emergencyAdmin,
          IERC20Burnable(address(splitToken)),
          DEFAULT_BURN_BPS,
          _distributors
        )
      )
    );
  }

  function testFuzz_RevertWhen_InitialDistributorWeightIsZero(
    address _admin,
    address _emergencyAdmin,
    address _recipient
  ) public {
    _assumeNonZeroAddress(_admin);
    _assumeNonZeroAddress(_emergencyAdmin);
    _assumeNonZeroAddress(_recipient);

    Splitter.DistributorConfig[] memory _distributors = _createDistributors(_recipient, 0);
    Splitter _implementation = new Splitter();
    vm.expectRevert(Splitter.Splitter_InvalidWeight.selector);
    new ERC1967Proxy(
      address(_implementation),
      abi.encodeCall(
        Splitter.initialize,
        (
          _admin,
          _emergencyAdmin,
          IERC20Burnable(address(splitToken)),
          DEFAULT_BURN_BPS,
          _distributors
        )
      )
    );
  }

  function testFuzz_RevertWhen_BurnBpsExceedsOneHundredPercent(uint256 _burnBps) public {
    _burnBps = bound(_burnBps, 10_001, type(uint256).max);

    Splitter.DistributorConfig[] memory _emptyDistributors = new Splitter.DistributorConfig[](0);
    Splitter _implementation = new Splitter();
    vm.expectRevert(Splitter.Splitter_InvalidBurnPercentage.selector);
    new ERC1967Proxy(
      address(_implementation),
      abi.encodeCall(
        Splitter.initialize,
        (admin, emergencyAdmin, IERC20Burnable(address(splitToken)), _burnBps, _emptyDistributors)
      )
    );
  }

  function testFuzz_RevertWhen_NoDistributorsAndBurnBpsLessThanOneHundredPercent(uint256 _burnBps)
    public
  {
    _burnBps = bound(_burnBps, 0, 9999);

    Splitter.DistributorConfig[] memory _emptyDistributors = new Splitter.DistributorConfig[](0);
    Splitter _implementation = new Splitter();
    vm.expectRevert(Splitter.Splitter_InvalidBurnPercentage.selector);
    new ERC1967Proxy(
      address(_implementation),
      abi.encodeCall(
        Splitter.initialize,
        (admin, emergencyAdmin, IERC20Burnable(address(splitToken)), _burnBps, _emptyDistributors)
      )
    );
  }

  function test_RevertWhen_InitializeCalledTwice() public {
    Splitter.DistributorConfig[] memory _emptyDistributors = new Splitter.DistributorConfig[](0);
    vm.expectRevert();
    splitter.initialize(
      admin,
      emergencyAdmin,
      IERC20Burnable(address(splitToken)),
      DEFAULT_BURN_BPS,
      _emptyDistributors
    );
  }

  function test_RevertWhen_ImplementationInitialized() public {
    Splitter.DistributorConfig[] memory _emptyDistributors = new Splitter.DistributorConfig[](0);
    Splitter _implementation = new Splitter();
    vm.expectRevert();
    _implementation.initialize(
      admin,
      emergencyAdmin,
      IERC20Burnable(address(splitToken)),
      DEFAULT_BURN_BPS,
      _emptyDistributors
    );
  }
}

contract SetDistributors is SplitterTest {
  function testFuzz_SetDistributors_ByAdmin(address _recipient, uint256 _weight) public {
    _assumeNonZeroAddress(_recipient);
    _weight = _boundWeight(_weight);

    Splitter.DistributorConfig[] memory _distributors = _createDistributors(_recipient, _weight);

    vm.prank(admin);
    splitter.setDistributors(_distributors);

    Splitter.DistributorConfig[] memory _result = splitter.distributors();
    assertEq(_result.length, 1);
    assertEq(_result[0].recipient, _recipient);
    assertEq(_result[0].weight, _weight);
    assertEq(splitter.totalDistributorWeight(), _weight);
  }

  function testFuzz_SetDistributors_ByEmergencyAdmin(address _recipient, uint256 _weight) public {
    _assumeNonZeroAddress(_recipient);
    _weight = _boundWeight(_weight);

    Splitter.DistributorConfig[] memory _distributors = _createDistributors(_recipient, _weight);

    vm.prank(emergencyAdmin);
    splitter.setDistributors(_distributors);

    Splitter.DistributorConfig[] memory _result = splitter.distributors();
    assertEq(_result.length, 1);
    assertEq(_result[0].recipient, _recipient);
    assertEq(_result[0].weight, _weight);
    assertEq(splitter.totalDistributorWeight(), _weight);
  }

  function testFuzz_SetDistributors_EmitsEvent(address _recipient, uint256 _weight) public {
    _assumeNonZeroAddress(_recipient);
    _weight = _boundWeight(_weight);

    Splitter.DistributorConfig[] memory _distributors = _createDistributors(_recipient, _weight);

    vm.expectEmit();
    emit Splitter.DistributorsSet(_distributors);

    vm.prank(admin);
    splitter.setDistributors(_distributors);
  }

  function testFuzz_SetDistributors_MultipleDistributors(
    address _recipient1,
    address _recipient2,
    uint256 _weight1,
    uint256 _weight2
  ) public {
    _assumeNonZeroAddress(_recipient1);
    _assumeNonZeroAddress(_recipient2);
    _weight1 = _boundWeight(_weight1);
    _weight2 = _boundWeight(_weight2);

    Splitter.DistributorConfig[] memory _distributors =
      _createDistributors(_recipient1, _weight1, _recipient2, _weight2);

    vm.prank(admin);
    splitter.setDistributors(_distributors);

    Splitter.DistributorConfig[] memory _result = splitter.distributors();
    assertEq(_result.length, 2);
    assertEq(_result[0].recipient, _recipient1);
    assertEq(_result[0].weight, _weight1);
    assertEq(_result[1].recipient, _recipient2);
    assertEq(_result[1].weight, _weight2);
    assertEq(splitter.totalDistributorWeight(), _weight1 + _weight2);
  }

  function testFuzz_SetDistributors_ReplacesExistingConfiguration(
    address _recipient1,
    address _recipient2,
    uint256 _weight1,
    uint256 _weight2
  ) public {
    _assumeNonZeroAddress(_recipient1);
    _assumeNonZeroAddress(_recipient2);
    vm.assume(_recipient1 != _recipient2);
    _weight1 = _boundWeight(_weight1);
    _weight2 = _boundWeight(_weight2);

    // Set initial configuration
    Splitter.DistributorConfig[] memory _initialDistributors =
      _createDistributors(_recipient1, _weight1);
    vm.prank(admin);
    splitter.setDistributors(_initialDistributors);

    // Replace with new configuration
    Splitter.DistributorConfig[] memory _newDistributors =
      _createDistributors(_recipient2, _weight2);
    vm.prank(admin);
    splitter.setDistributors(_newDistributors);

    Splitter.DistributorConfig[] memory _result = splitter.distributors();
    assertEq(_result.length, 1);
    assertEq(_result[0].recipient, _recipient2);
    assertEq(_result[0].weight, _weight2);
    assertEq(splitter.totalDistributorWeight(), _weight2);
  }

  function test_SetDistributors_EmptyArray() public {
    // First set some distributors
    address _recipient = makeAddr("recipient");
    uint256 _weight = 100;
    Splitter.DistributorConfig[] memory _distributors = _createDistributors(_recipient, _weight);
    vm.prank(admin);
    splitter.setDistributors(_distributors);

    // Now clear with empty array
    Splitter.DistributorConfig[] memory _emptyDistributors = new Splitter.DistributorConfig[](0);
    vm.prank(admin);
    splitter.setDistributors(_emptyDistributors);

    assertEq(splitter.distributors().length, 0);
    assertEq(splitter.totalDistributorWeight(), 0);
  }

  function testFuzz_SetDistributors_EmptyArrayForcesBurnToOneHundredPercent(
    address _recipient,
    uint256 _weight,
    uint256 _burnBps
  ) public {
    _assumeNonZeroAddress(_recipient);
    _weight = _boundWeight(_weight);
    _burnBps = bound(_burnBps, 0, 9999);

    // First set some distributors (starts at 100% burn)
    Splitter.DistributorConfig[] memory _distributors = _createDistributors(_recipient, _weight);
    vm.prank(admin);
    splitter.setDistributors(_distributors);

    // Now reduce burn percentage (allowed since we have distributors)
    vm.prank(admin);
    splitter.setBurnPercentage(_burnBps);
    assertEq(splitter.burnPercentage(), _burnBps);

    // Clear with empty array should force burn to 100%
    Splitter.DistributorConfig[] memory _emptyDistributors = new Splitter.DistributorConfig[](0);
    vm.expectEmit();
    emit Splitter.BurnPercentageSet(_burnBps, DEFAULT_BURN_BPS);
    vm.prank(admin);
    splitter.setDistributors(_emptyDistributors);

    assertEq(splitter.burnPercentage(), DEFAULT_BURN_BPS);
  }

  function testFuzz_SetDistributors_EmptyArrayNoChangeWhenAlreadyOneHundredPercent(
    address _recipient,
    uint256 _weight
  ) public {
    _assumeNonZeroAddress(_recipient);
    _weight = _boundWeight(_weight);

    // Default setup is 100% burn
    assertEq(splitter.burnPercentage(), DEFAULT_BURN_BPS);

    // First set some distributors
    Splitter.DistributorConfig[] memory _distributors = _createDistributors(_recipient, _weight);
    vm.prank(admin);
    splitter.setDistributors(_distributors);

    // Clear with empty array - burn percentage should stay at 100%
    Splitter.DistributorConfig[] memory _emptyDistributors = new Splitter.DistributorConfig[](0);
    vm.prank(admin);
    splitter.setDistributors(_emptyDistributors);

    // Burn percentage should still be 100%
    assertEq(splitter.burnPercentage(), DEFAULT_BURN_BPS);
  }

  function testFuzz_SetDistributors_DuplicateRecipientsAllowed(
    address _recipient,
    uint256 _weight1,
    uint256 _weight2
  ) public {
    _assumeNonZeroAddress(_recipient);
    _weight1 = _boundWeight(_weight1);
    _weight2 = _boundWeight(_weight2);

    // Same recipient appears twice with different weights
    Splitter.DistributorConfig[] memory _distributors =
      _createDistributors(_recipient, _weight1, _recipient, _weight2);

    vm.prank(admin);
    splitter.setDistributors(_distributors);

    Splitter.DistributorConfig[] memory _result = splitter.distributors();
    assertEq(_result.length, 2);
    assertEq(_result[0].recipient, _recipient);
    assertEq(_result[0].weight, _weight1);
    assertEq(_result[1].recipient, _recipient);
    assertEq(_result[1].weight, _weight2);
    assertEq(splitter.totalDistributorWeight(), _weight1 + _weight2);
  }

  function testFuzz_RevertWhen_SetDistributors_CalledByNonAdmin(
    address _caller,
    address _recipient,
    uint256 _weight
  ) public {
    _assumeNotAdmin(_caller);
    _assumeNonZeroAddress(_recipient);
    _weight = _boundWeight(_weight);

    Splitter.DistributorConfig[] memory _distributors = _createDistributors(_recipient, _weight);

    vm.prank(_caller);
    vm.expectRevert(Splitter.Splitter_Unauthorized.selector);
    splitter.setDistributors(_distributors);
  }

  function testFuzz_RevertWhen_SetDistributors_RecipientIsZeroAddress(uint256 _weight) public {
    _weight = _boundWeight(_weight);

    Splitter.DistributorConfig[] memory _distributors = _createDistributors(address(0), _weight);

    vm.prank(admin);
    vm.expectRevert(Splitter.Splitter_InvalidAddress.selector);
    splitter.setDistributors(_distributors);
  }

  function testFuzz_RevertWhen_SetDistributors_WeightIsZero(address _recipient) public {
    _assumeNonZeroAddress(_recipient);

    Splitter.DistributorConfig[] memory _distributors = _createDistributors(_recipient, 0);

    vm.prank(admin);
    vm.expectRevert(Splitter.Splitter_InvalidWeight.selector);
    splitter.setDistributors(_distributors);
  }

  function testFuzz_RevertWhen_SetDistributors_SecondRecipientIsZeroAddress(
    address _recipient1,
    uint256 _weight1,
    uint256 _weight2
  ) public {
    _assumeNonZeroAddress(_recipient1);
    _weight1 = _boundWeight(_weight1);
    _weight2 = _boundWeight(_weight2);

    Splitter.DistributorConfig[] memory _distributors =
      _createDistributors(_recipient1, _weight1, address(0), _weight2);

    vm.prank(admin);
    vm.expectRevert(Splitter.Splitter_InvalidAddress.selector);
    splitter.setDistributors(_distributors);
  }

  function testFuzz_RevertWhen_SetDistributors_SecondWeightIsZero(
    address _recipient1,
    address _recipient2,
    uint256 _weight1
  ) public {
    _assumeNonZeroAddress(_recipient1);
    _assumeNonZeroAddress(_recipient2);
    _weight1 = _boundWeight(_weight1);

    Splitter.DistributorConfig[] memory _distributors =
      _createDistributors(_recipient1, _weight1, _recipient2, 0);

    vm.prank(admin);
    vm.expectRevert(Splitter.Splitter_InvalidWeight.selector);
    splitter.setDistributors(_distributors);
  }
}

contract UpgradeToAndCall is SplitterTest {
  function test_Upgrade_ByAdmin() public {
    Splitter _newImplementation = new Splitter();

    vm.prank(admin);
    splitter.upgradeToAndCall(address(_newImplementation), "");
  }

  function test_Upgrade_PreservesStorage() public {
    address _recipient = makeAddr("recipient");
    uint256 _weight = 100;

    Splitter.DistributorConfig[] memory _distributors = _createDistributors(_recipient, _weight);
    vm.prank(admin);
    splitter.setDistributors(_distributors);

    Splitter _newImplementation = new Splitter();

    vm.prank(admin);
    splitter.upgradeToAndCall(address(_newImplementation), "");

    assertTrue(splitter.hasRole(splitter.DEFAULT_ADMIN_ROLE(), admin));
    assertTrue(splitter.hasRole(splitter.EMERGENCY_ADMIN_ROLE(), emergencyAdmin));
    Splitter.DistributorConfig[] memory _result = splitter.distributors();
    assertEq(_result.length, 1);
    assertEq(_result[0].recipient, _recipient);
    assertEq(_result[0].weight, _weight);
    assertEq(splitter.totalDistributorWeight(), _weight);
  }

  function test_RevertWhen_Upgrade_CalledByEmergencyAdmin() public {
    Splitter _newImplementation = new Splitter();

    vm.prank(emergencyAdmin);
    vm.expectRevert(Splitter.Splitter_Unauthorized.selector);
    splitter.upgradeToAndCall(address(_newImplementation), "");
  }

  function testFuzz_RevertWhen_Upgrade_CalledByNonAdmin(address _caller) public {
    _assumeNotAdmin(_caller);

    Splitter _newImplementation = new Splitter();

    vm.prank(_caller);
    vm.expectRevert(Splitter.Splitter_Unauthorized.selector);
    splitter.upgradeToAndCall(address(_newImplementation), "");
  }
}

contract SetBurnPercentage is SplitterTest {
  function testFuzz_SetBurnPercentage_ByAdmin(uint256 _newBurnBps) public {
    _addDistributor();
    _newBurnBps = bound(_newBurnBps, 0, DEFAULT_BURN_BPS);

    vm.prank(admin);
    splitter.setBurnPercentage(_newBurnBps);

    assertEq(splitter.burnPercentage(), _newBurnBps);
    assertEq(splitter.distributedPercentage(), DEFAULT_BURN_BPS - _newBurnBps);
  }

  function testFuzz_SetBurnPercentage_ByEmergencyAdmin(uint256 _newBurnBps) public {
    _addDistributor();
    _newBurnBps = bound(_newBurnBps, 0, DEFAULT_BURN_BPS);

    vm.prank(emergencyAdmin);
    splitter.setBurnPercentage(_newBurnBps);

    assertEq(splitter.burnPercentage(), _newBurnBps);
  }

  function testFuzz_SetBurnPercentage_EmitsEvent(uint256 _newBurnBps) public {
    _addDistributor();
    _newBurnBps = bound(_newBurnBps, 0, DEFAULT_BURN_BPS);
    uint256 _oldBurnBps = splitter.burnPercentage();

    vm.expectEmit();
    emit Splitter.BurnPercentageSet(_oldBurnBps, _newBurnBps);

    vm.prank(admin);
    splitter.setBurnPercentage(_newBurnBps);
  }

  function testFuzz_RevertWhen_SetBurnPercentage_CalledByNonAdmin(
    address _caller,
    uint256 _newBurnBps
  ) public {
    _addDistributor();
    _assumeNotAdmin(_caller);
    _newBurnBps = bound(_newBurnBps, 0, DEFAULT_BURN_BPS);

    vm.prank(_caller);
    vm.expectRevert(Splitter.Splitter_Unauthorized.selector);
    splitter.setBurnPercentage(_newBurnBps);
  }

  function testFuzz_RevertWhen_SetBurnPercentage_ExceedsOneHundredPercent(uint256 _newBurnBps)
    public
  {
    _addDistributor();
    _newBurnBps = bound(_newBurnBps, 10_001, type(uint256).max);

    vm.prank(admin);
    vm.expectRevert(Splitter.Splitter_InvalidBurnPercentage.selector);
    splitter.setBurnPercentage(_newBurnBps);
  }

  function testFuzz_RevertWhen_SetBurnPercentage_NoDistributorsAndNotFull(uint256 _newBurnBps)
    public
  {
    _newBurnBps = bound(_newBurnBps, 0, 9999);

    vm.prank(admin);
    vm.expectRevert(Splitter.Splitter_InvalidBurnPercentage.selector);
    splitter.setBurnPercentage(_newBurnBps);
  }

  function test_SetBurnPercentage_NoDistributorsAllows100() public {
    vm.prank(admin);
    splitter.setBurnPercentage(DEFAULT_BURN_BPS);

    assertEq(splitter.burnPercentage(), DEFAULT_BURN_BPS);
  }
}

contract Split is SplitterTest {
  function testFuzz_DistributesToSingleDistributor(
    address _caller,
    address _recipient,
    uint256 _weight,
    uint256 _amount
  ) public {
    _assumeNonZeroAddress(_caller);
    _assumeNonZeroAddress(_recipient);
    _assumeNotSplitter(_recipient);
    _weight = _boundWeight(_weight);
    _amount = bound(_amount, 1, type(uint128).max);

    // Set 0% burn so all goes to distributor
    _addDistributors(_recipient, _weight);
    _setBurnBps(0);
    _mintToSplitter(_amount);

    uint256 _splitterBalanceBefore = splitToken.balanceOf(address(splitter));
    uint256 _recipientBalanceBefore = splitToken.balanceOf(_recipient);
    uint256 _totalSupplyBefore = splitToken.totalSupply();

    // split() is permissionless.
    vm.prank(_caller);
    splitter.split();

    uint256 _recipientBalanceAfter = splitToken.balanceOf(_recipient);
    uint256 _distributed = _recipientBalanceAfter - _recipientBalanceBefore;
    uint256 _burned = _totalSupplyBefore - splitToken.totalSupply();

    assertEq(_distributed + _burned, _splitterBalanceBefore);
    // Rounding dust is always < distributor count; here burned is <= 1 wei.
    assertLe(_burned, 1);
    assertEq(splitToken.balanceOf(address(splitter)), 0);
  }

  function testFuzz_DistributesToMultipleDistributors(
    address _recipient1,
    address _recipient2,
    uint256 _weight1,
    uint256 _weight2,
    uint256 _amount
  ) public {
    _assumeNonZeroAddress(_recipient1);
    _assumeNonZeroAddress(_recipient2);
    _assumeNotSplitter(_recipient1);
    _assumeNotSplitter(_recipient2);
    vm.assume(_recipient1 != _recipient2);
    _weight1 = _boundWeight(_weight1);
    _weight2 = _boundWeight(_weight2);
    _amount = bound(_amount, 1, type(uint128).max);

    Splitter.DistributorConfig[] memory _distributors =
      _createDistributors(_recipient1, _weight1, _recipient2, _weight2);
    vm.prank(admin);
    splitter.setDistributors(_distributors);
    _setBurnBps(0);

    _mintToSplitter(_amount);

    uint256 _splitterBalanceBefore = splitToken.balanceOf(address(splitter));
    uint256 _recipient1BalanceBefore = splitToken.balanceOf(_recipient1);
    uint256 _recipient2BalanceBefore = splitToken.balanceOf(_recipient2);
    uint256 _totalSupplyBefore = splitToken.totalSupply();

    splitter.split();

    uint256 _recipient1BalanceAfter = splitToken.balanceOf(_recipient1);
    uint256 _recipient2BalanceAfter = splitToken.balanceOf(_recipient2);
    uint256 _distributed = (_recipient1BalanceAfter - _recipient1BalanceBefore)
      + (_recipient2BalanceAfter - _recipient2BalanceBefore);
    uint256 _burned = _totalSupplyBefore - splitToken.totalSupply();

    assertEq(_distributed + _burned, _splitterBalanceBefore);
    // Rounding dust is always < distributor count; with 2 distributors, burned is <= 1 wei.
    assertLe(_burned, 1);
    assertEq(splitToken.balanceOf(address(splitter)), 0);
  }

  function testFuzz_DistributesAllTokensWhenBurnIsZeroPercent(
    address _recipient,
    uint256 _weight,
    uint256 _amount
  ) public {
    _assumeNonZeroAddress(_recipient);
    _assumeNotSplitter(_recipient);
    _weight = _boundWeight(_weight);
    _amount = bound(_amount, 1, type(uint128).max);

    _addDistributors(_recipient, _weight);
    _setBurnBps(0);
    _mintToSplitter(_amount);

    uint256 _splitterBalanceBefore = splitToken.balanceOf(address(splitter));
    uint256 _recipientBalanceBefore = splitToken.balanceOf(_recipient);
    uint256 _totalSupplyBefore = splitToken.totalSupply();

    splitter.split();

    uint256 _recipientBalanceAfter = splitToken.balanceOf(_recipient);
    uint256 _distributed = _recipientBalanceAfter - _recipientBalanceBefore;
    uint256 _burned = _totalSupplyBefore - splitToken.totalSupply();

    assertEq(_burned, 0);
    assertEq(_distributed, _splitterBalanceBefore);
    assertEq(splitToken.balanceOf(address(splitter)), 0);
  }

  function testFuzz_BurnsDustFromRounding(address _recipient1, address _recipient2, uint256 _amount)
    public
  {
    _assumeNonZeroAddress(_recipient1);
    _assumeNonZeroAddress(_recipient2);
    _assumeNotSplitter(_recipient1);
    _assumeNotSplitter(_recipient2);
    vm.assume(_recipient1 != _recipient2);
    // Use an amount that will produce dust with these weights
    _amount = bound(_amount, 100, type(uint128).max);
    vm.assume(_amount % 3 != 0);

    // Set up 2 distributors with weights that will cause rounding
    // weights 1 and 2 -> total 3, amounts not divisible by 3 will have dust
    _addTwoDistributors(_recipient1, 1, _recipient2, 2);
    _setBurnBps(0);

    _mintToSplitter(_amount);

    uint256 _totalSupplyBefore = splitToken.totalSupply();
    uint256 _share1 = (_amount * 1) / 3;
    uint256 _share2 = (_amount * 2) / 3;
    uint256 _dust = _amount - _share1 - _share2;

    splitter.split();

    assertEq(splitToken.balanceOf(_recipient1), _share1);
    assertEq(splitToken.balanceOf(_recipient2), _share2);
    // Dust was burned
    assertEq(splitToken.totalSupply(), _totalSupplyBefore - _dust);
    assertEq(splitToken.balanceOf(address(splitter)), 0);
  }

  function testFuzz_BurnsDustFromRounding_WhenBurnBpsSet(
    address _recipient1,
    address _recipient2,
    uint256 _burnBps,
    uint256 _amount
  ) public {
    _assumeNonZeroAddress(_recipient1);
    _assumeNonZeroAddress(_recipient2);
    _assumeNotSplitter(_recipient1);
    _assumeNotSplitter(_recipient2);
    vm.assume(_recipient1 != _recipient2);

    _burnBps = bound(_burnBps, 1, BPS_DENOMINATOR - 1);
    _amount = bound(_amount, 100, type(uint128).max);

    _addTwoDistributors(_recipient1, 1, _recipient2, 2);
    _setBurnBps(_burnBps);

    _mintToSplitter(_amount);

    uint256 _splitterBalanceBefore = splitToken.balanceOf(address(splitter));
    uint256 _expectedBurn = (_splitterBalanceBefore * _burnBps) / BPS_DENOMINATOR;
    uint256 _expectedDistribute = _splitterBalanceBefore - _expectedBurn;
    // Ensure the distributable amount produces dust with weights 1 and 2 (total 3).
    vm.assume(_expectedDistribute % 3 != 0);

    uint256 _recipient1BalanceBefore = splitToken.balanceOf(_recipient1);
    uint256 _recipient2BalanceBefore = splitToken.balanceOf(_recipient2);
    uint256 _totalSupplyBefore = splitToken.totalSupply();

    splitter.split();

    uint256 _recipient1BalanceAfter = splitToken.balanceOf(_recipient1);
    uint256 _recipient2BalanceAfter = splitToken.balanceOf(_recipient2);

    uint256 _distributed = (_recipient1BalanceAfter - _recipient1BalanceBefore)
      + (_recipient2BalanceAfter - _recipient2BalanceBefore);
    uint256 _burned = _totalSupplyBefore - splitToken.totalSupply();

    assertEq(_distributed + _burned, _splitterBalanceBefore);
    assertGt(_burned, _expectedBurn);
    assertEq(splitToken.balanceOf(address(splitter)), 0);
  }

  function testFuzz_EmitsSplitEvent(
    address _recipient,
    uint256 _weight,
    uint256 _burnBps,
    uint256 _amount
  ) public {
    _assumeNonZeroAddress(_recipient);
    _assumeNotSplitter(_recipient);
    _weight = _boundWeight(_weight);
    _burnBps = bound(_burnBps, 0, 10_000);
    _amount = bound(_amount, 1, type(uint128).max);

    _addDistributors(_recipient, _weight);
    _setBurnBps(_burnBps);
    _mintToSplitter(_amount);

    uint256 _expectedBurn = (_amount * _burnBps) / BPS_DENOMINATOR;
    uint256 _expectedDistribute = _amount - _expectedBurn;

    vm.expectEmit();
    emit Splitter.Split(_amount, _expectedBurn, _expectedDistribute);

    splitter.split();
  }

  function testFuzz_ZeroBalanceIsNoOp(address _recipient, uint256 _weight) public {
    _assumeNonZeroAddress(_recipient);
    _assumeNotSplitter(_recipient);
    _weight = _boundWeight(_weight);

    _addDistributors(_recipient, _weight);
    _setBurnBps(5000);
    // Don't mint any tokens - balance is 0

    uint256 _totalSupplyBefore = splitToken.totalSupply();
    vm.recordLogs();
    splitter.split();
    Vm.Log[] memory _entries = vm.getRecordedLogs();

    assertEq(splitToken.balanceOf(_recipient), 0);
    assertEq(splitToken.balanceOf(address(splitter)), 0);
    assertEq(splitToken.totalSupply(), _totalSupplyBefore);
    assertEq(_entries.length, 0);
  }

  function testFuzz_NoDistributors_EmitsSplitEventAndBurnsAll(uint256 _amount) public {
    _amount = bound(_amount, 1, type(uint128).max);

    // Default setup has no distributors, 100% burn
    _mintToSplitter(_amount);

    uint256 _totalSupplyBefore = splitToken.totalSupply();

    vm.expectEmit();
    emit Splitter.Split(_amount, _amount, 0);

    splitter.split();

    // All burned
    assertEq(splitToken.totalSupply(), _totalSupplyBefore - _amount);
    assertEq(splitToken.balanceOf(address(splitter)), 0);
  }

  function testFuzz_BurnedIsExpectedBurnPlusAtMostOneWei(
    address _recipient1,
    address _recipient2,
    uint256 _weight1,
    uint256 _weight2,
    uint256 _burnBps,
    uint256 _amount
  ) public {
    _assumeNonZeroAddress(_recipient1);
    _assumeNonZeroAddress(_recipient2);
    _assumeNotSplitter(_recipient1);
    _assumeNotSplitter(_recipient2);
    vm.assume(_recipient1 != _recipient2);

    _weight1 = _boundWeight(_weight1);
    _weight2 = _boundWeight(_weight2);
    _burnBps = bound(_burnBps, 0, BPS_DENOMINATOR);
    _amount = bound(_amount, 1, type(uint128).max);

    _addTwoDistributors(_recipient1, _weight1, _recipient2, _weight2);
    _setBurnBps(_burnBps);
    _mintToSplitter(_amount);

    uint256 _splitterBalanceBefore = splitToken.balanceOf(address(splitter));
    uint256 _recipient1BalanceBefore = splitToken.balanceOf(_recipient1);
    uint256 _recipient2BalanceBefore = splitToken.balanceOf(_recipient2);
    uint256 _totalSupplyBefore = splitToken.totalSupply();

    uint256 _expectedBurn = (_splitterBalanceBefore * _burnBps) / BPS_DENOMINATOR;

    splitter.split();

    uint256 _recipient1BalanceAfter = splitToken.balanceOf(_recipient1);
    uint256 _recipient2BalanceAfter = splitToken.balanceOf(_recipient2);
    uint256 _distributed = (_recipient1BalanceAfter - _recipient1BalanceBefore)
      + (_recipient2BalanceAfter - _recipient2BalanceBefore);
    uint256 _burned = _totalSupplyBefore - splitToken.totalSupply();

    // With 2 distributors, rounding dust is <= 1 wei.
    assertGe(_burned, _expectedBurn);
    assertLe(_burned, _expectedBurn + 1);
    assertEq(_distributed + _burned, _splitterBalanceBefore);
    assertEq(splitToken.balanceOf(address(splitter)), 0);
  }
}

contract Recover is SplitterTest {
  function testFuzz_RecoversTokensWhenCalledByAdmin(address _to, uint256 _amount) public {
    vm.assume(_to != address(0) && _to != address(splitter));

    ERC20BurnableMock _token = new ERC20BurnableMock();
    _token.mint(address(splitter), _amount);

    vm.prank(admin);
    splitter.recover(IERC20(address(_token)), _to, _amount);

    assertEq(_token.balanceOf(_to), _amount);
    assertEq(_token.balanceOf(address(splitter)), 0);
  }

  function testFuzz_EmitsEvent_WhenTokensRecovered(address _to, uint256 _amount) public {
    vm.assume(_to != address(0));

    ERC20BurnableMock _token = new ERC20BurnableMock();
    _token.mint(address(splitter), _amount);

    vm.expectEmit(address(splitter));
    emit Splitter.Recovered(IERC20(address(_token)), _to, _amount);

    vm.prank(admin);
    splitter.recover(IERC20(address(_token)), _to, _amount);
  }

  function testFuzz_RevertWhen_CallerIsNotAdmin(address _caller, address _to, uint256 _amount)
    public
  {
    _assumeNotAdmin(_caller);

    ERC20BurnableMock _token = new ERC20BurnableMock();
    _token.mint(address(splitter), _amount);

    vm.prank(_caller);
    vm.expectRevert(Splitter.Splitter_Unauthorized.selector);
    splitter.recover(IERC20(address(_token)), _to, _amount);
  }

  function test_RevertWhen_CallerIsEmergencyAdmin() public {
    ERC20BurnableMock _token = new ERC20BurnableMock();
    _token.mint(address(splitter), 1000);

    vm.prank(emergencyAdmin);
    vm.expectRevert(Splitter.Splitter_Unauthorized.selector);
    splitter.recover(IERC20(address(_token)), makeAddr("recipient"), 1000);
  }

  function testFuzz_RevertWhen_InsufficientBalance(address _to, uint256 _balance, uint256 _amount)
    public
  {
    vm.assume(_to != address(0));
    _balance = bound(_balance, 0, type(uint128).max);
    _amount = bound(_amount, _balance + 1, type(uint256).max);

    ERC20BurnableMock _token = new ERC20BurnableMock();
    _token.mint(address(splitter), _balance);

    vm.prank(admin);
    vm.expectRevert();
    splitter.recover(IERC20(address(_token)), _to, _amount);
  }

  function testFuzz_RevertWhen_ToIsZeroAddress(uint256 _amount) public {
    ERC20BurnableMock _token = new ERC20BurnableMock();
    _token.mint(address(splitter), _amount);

    vm.prank(admin);
    vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
    splitter.recover(IERC20(address(_token)), address(0), _amount);
  }
}
