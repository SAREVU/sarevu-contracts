// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../core/ProtocolRegistry.sol";

contract ProtocolRegistryTest is Test {
    ProtocolRegistry internal registry;

    address internal owner = address(0xA11CE);
    address internal newOwner = address(0xB0B);
    address internal attacker = address(0xDEAD);

    bytes32 internal constant TEST_KEY = keccak256("TEST_PARAMETER");
    bytes32 internal constant UNKNOWN_KEY = keccak256("UNKNOWN_PARAMETER");

    bytes32 internal constant KEY_BOOKING = keccak256("BOOKING_COOLDOWN");
    bytes32 internal constant KEY_DISPUTE = keccak256("DISPUTE_WINDOW");
    bytes32 internal constant KEY_PAYOUT = keccak256("PAYOUT_DELAY");
    bytes32 internal constant KEY_EVIDENCE = keccak256("EVIDENCE_WINDOW");
    bytes32 internal constant KEY_TL_STD = keccak256("TIMELOCK_STANDARD");
    bytes32 internal constant KEY_TL_CRIT = keccak256("TIMELOCK_CRITICAL");

    event ParameterRegistered(bytes32 indexed key, uint256 initialValue, uint256 floor);
    event ParameterSet(bytes32 indexed key, uint256 oldValue, uint256 newValue, address indexed by);
    event FloorUpdated(bytes32 indexed key, uint256 oldFloor, uint256 newFloor);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        vm.prank(owner);
        registry = new ProtocolRegistry(owner);
    }

    function _register(bytes32 key, uint256 initialValue, uint256 floor) internal {
        vm.prank(owner);
        registry.registerParameter(key, initialValue, floor);
    }

    function _registerCanonicalSet() internal {
        _register(KEY_BOOKING, 86400, 3600);
        _register(KEY_DISPUTE, 604800, 86400);
        _register(KEY_PAYOUT, 172800, 3600);
        _register(KEY_EVIDENCE, 259200, 43200);
        _register(KEY_TL_STD, 172800, 3600);
        _register(KEY_TL_CRIT, 259200, 172800);
    }

    // ---------------- Baseline Task 1 DoD: T1-01 ... T1-19 ----------------

    function test_T1_01_ConstructorValidOwner() public {
        vm.prank(owner);
        ProtocolRegistry deployed = new ProtocolRegistry(owner);
        assertEq(deployed.owner(), owner);
    }

    function test_T1_02_ConstructorZeroAddress() public {
        vm.expectRevert(ProtocolRegistry.ZeroAddress.selector);
        new ProtocolRegistry(address(0));
    }

    function test_T1_03_RegisterParameterSuccessAndEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ParameterRegistered(TEST_KEY, 100, 10);

        vm.prank(owner);
        registry.registerParameter(TEST_KEY, 100, 10);

        assertEq(registry.getParameter(TEST_KEY), 100);
        assertEq(registry.getFloor(TEST_KEY), 10);
        assertTrue(registry.parameterExists(TEST_KEY));
    }

    function test_T1_04_RegisterParameterDuplicateKey() public {
        _register(TEST_KEY, 100, 10);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtocolRegistry.ParameterAlreadyExists.selector, TEST_KEY));
        registry.registerParameter(TEST_KEY, 200, 20);
    }

    function test_T1_05_RegisterParameterBelowFloor() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtocolRegistry.BelowSafetyFloor.selector, TEST_KEY, 50, 100));
        registry.registerParameter(TEST_KEY, 50, 100);

        assertFalse(registry.parameterExists(TEST_KEY));
    }

    function test_T1_06_SetParameterValid() public {
        _register(TEST_KEY, 100, 10);

        vm.prank(owner);
        registry.setParameter(TEST_KEY, 200);

        assertEq(registry.getParameter(TEST_KEY), 200);
    }

    function test_T1_07_SetParameterBelowFloorValueUnchanged() public {
        _register(TEST_KEY, 100, 10);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtocolRegistry.BelowSafetyFloor.selector, TEST_KEY, 5, 10));
        registry.setParameter(TEST_KEY, 5);

        assertEq(registry.getParameter(TEST_KEY), 100);
    }

    function test_T1_08_SetParameterExactlyAtFloor() public {
        _register(TEST_KEY, 100, 10);

        vm.prank(owner);
        registry.setParameter(TEST_KEY, 10);

        assertEq(registry.getParameter(TEST_KEY), 10);
    }

    function test_T1_09_SetParameterUnauthorizedCaller() public {
        _register(TEST_KEY, 100, 10);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        registry.setParameter(TEST_KEY, 200);
    }

    function test_T1_10_SetParameterEventContainsOldValue() public {
        _register(TEST_KEY, 100, 10);

        vm.expectEmit(true, false, false, true);
        emit ParameterSet(TEST_KEY, 100, 200, owner);

        vm.prank(owner);
        registry.setParameter(TEST_KEY, 200);
    }

    function test_T1_11_GetParameterUnknownKey() public {
        vm.expectRevert(abi.encodeWithSelector(ProtocolRegistry.ParameterNotFound.selector, UNKNOWN_KEY));
        registry.getParameter(UNKNOWN_KEY);
    }

    function test_T1_12_IsBelowFloorTrue() public {
        _register(TEST_KEY, 100, 100);
        assertTrue(registry.isBelowFloor(TEST_KEY, 50));
    }

    function test_T1_13_IsBelowFloorFalseAtFloor() public {
        _register(TEST_KEY, 100, 100);
        assertFalse(registry.isBelowFloor(TEST_KEY, 100));
        assertFalse(registry.isBelowFloor(TEST_KEY, 200));
    }

    function test_T1_14_PauseBlocksSetParameter() public {
        _register(TEST_KEY, 100, 10);

        vm.expectEmit(false, false, false, true);
        emit Paused(owner);

        vm.prank(owner);
        registry.pause();

        vm.prank(owner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        registry.setParameter(TEST_KEY, 200);
    }

    function test_T1_15_PauseDoesNotBlockGetParameter() public {
        _register(TEST_KEY, 100, 10);

        vm.prank(owner);
        registry.pause();

        assertEq(registry.getParameter(TEST_KEY), 100);
    }

    function test_T1_16_UnpauseRestoresSetParameter() public {
        _register(TEST_KEY, 100, 10);

        vm.prank(owner);
        registry.pause();

        vm.expectEmit(false, false, false, true);
        emit Unpaused(owner);

        vm.prank(owner);
        registry.unpause();

        vm.prank(owner);
        registry.setParameter(TEST_KEY, 200);

        assertEq(registry.getParameter(TEST_KEY), 200);
    }

    function test_T1_17_OwnershipTransferOldOwnerLosesRights() public {
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferStarted(owner, newOwner);

        vm.prank(owner);
        registry.transferOwnership(newOwner);

        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(owner, newOwner);

        vm.prank(newOwner);
        registry.acceptOwnership();

        assertEq(registry.owner(), newOwner);

        vm.prank(newOwner);
        registry.registerParameter(TEST_KEY, 100, 10);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        registry.setParameter(TEST_KEY, 200);
    }

    function test_T1_18_SetFloorInvalid() public {
        _register(TEST_KEY, 100, 10);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtocolRegistry.InvalidFloor.selector, TEST_KEY, 150, 100));
        registry.setFloor(TEST_KEY, 150);
    }

    function testFuzz_T1_19_BelowFloorAlwaysReverts(uint256 randomValue) public {
        uint256 floor = 1000;
        vm.assume(randomValue < floor);

        _register(TEST_KEY, floor, floor);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtocolRegistry.BelowSafetyFloor.selector, TEST_KEY, randomValue, floor));
        registry.setParameter(TEST_KEY, randomValue);

        assertEq(registry.getParameter(TEST_KEY), floor);
    }

    // ---------------- Extra hardening tests ----------------

    function test_Extra_SetFloorValidUpdatesStoredValueAndEvent() public {
        _register(TEST_KEY, 100, 10);

        vm.expectEmit(true, false, false, true);
        emit FloorUpdated(TEST_KEY, 10, 50);

        vm.prank(owner);
        registry.setFloor(TEST_KEY, 50);

        assertEq(registry.getFloor(TEST_KEY), 50);
    }

    function test_Extra_GetFloorUnknownKeyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(ProtocolRegistry.ParameterNotFound.selector, UNKNOWN_KEY));
        registry.getFloor(UNKNOWN_KEY);
    }

    function test_Extra_ParameterExistsUnknownKeyReturnsFalse() public {
        assertFalse(registry.parameterExists(UNKNOWN_KEY));
    }

    function test_Extra_IsBelowFloorUnknownKeyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(ProtocolRegistry.ParameterNotFound.selector, UNKNOWN_KEY));
        registry.isBelowFloor(UNKNOWN_KEY, 1);
    }

    function test_Extra_SetFloorUnknownKeyReverts() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtocolRegistry.ParameterNotFound.selector, UNKNOWN_KEY));
        registry.setFloor(UNKNOWN_KEY, 1);
    }

    function test_Extra_SetParameterUnknownKeyReverts() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtocolRegistry.ParameterNotFound.selector, UNKNOWN_KEY));
        registry.setParameter(UNKNOWN_KEY, 1);
    }

    function test_Extra_PauseOnlyOwnerRevertsForAttacker() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        registry.pause();
    }

    function test_Extra_UnpauseOnlyOwnerRevertsForAttacker() public {
        vm.prank(owner);
        registry.pause();

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        registry.unpause();
    }

    function test_Extra_CanonicalParameterKeysInvariant() public pure {
        assertTrue(KEY_BOOKING != bytes32(0));
        assertTrue(KEY_DISPUTE != bytes32(0));
        assertTrue(KEY_PAYOUT != bytes32(0));
        assertTrue(KEY_EVIDENCE != bytes32(0));
        assertTrue(KEY_TL_STD != bytes32(0));
        assertTrue(KEY_TL_CRIT != bytes32(0));
        assertGe(uint256(KEY_TL_CRIT), uint256(KEY_TL_STD));
    }

    function test_Extra_CanonicalParameterRegistrationRoundtrip() public {
        _registerCanonicalSet();

        assertEq(registry.getParameter(KEY_BOOKING), 86400);
        assertEq(registry.getFloor(KEY_BOOKING), 3600);
        assertEq(registry.getParameter(KEY_DISPUTE), 604800);
        assertEq(registry.getFloor(KEY_DISPUTE), 86400);
        assertEq(registry.getParameter(KEY_PAYOUT), 172800);
        assertEq(registry.getFloor(KEY_PAYOUT), 3600);
        assertEq(registry.getParameter(KEY_EVIDENCE), 259200);
        assertEq(registry.getFloor(KEY_EVIDENCE), 43200);
        assertEq(registry.getParameter(KEY_TL_STD), 172800);
        assertEq(registry.getFloor(KEY_TL_STD), 3600);
        assertEq(registry.getParameter(KEY_TL_CRIT), 259200);
        assertEq(registry.getFloor(KEY_TL_CRIT), 172800);
    }
}
