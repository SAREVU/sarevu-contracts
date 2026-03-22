// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {EmergencyGuardian} from "../core/EmergencyGuardian.sol";

contract EmergencyGuardianTest is Test {
    EmergencyGuardian internal guardian;

    address internal admin = makeAddr("admin");
    address internal pauser = makeAddr("pauser");
    address internal attacker = makeAddr("attacker");

    bytes32 internal constant INVALID_SCOPE = keccak256("INVALID_SCOPE");

    event FreezeActivated(
        bytes32 indexed scope,
        string reason,
        uint256 timestamp,
        address indexed initiator
    );

    event FreezeDeactivated(
        bytes32 indexed scope,
        uint256 timestamp,
        address indexed initiator
    );

    function setUp() public {
        guardian = new EmergencyGuardian(admin, pauser);
    }

    function test_T4_01_ConstructorAssignsRolesCorrectly() public view {
        assertTrue(guardian.hasRole(guardian.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(guardian.hasRole(guardian.PAUSER_ROLE(), pauser));
        assertFalse(guardian.hasRole(guardian.DEFAULT_ADMIN_ROLE(), pauser));
        assertFalse(guardian.hasRole(guardian.PAUSER_ROLE(), admin));
    }

    function test_T4_02_RevertIf_ConstructorAdminZero() public {
        vm.expectRevert(EmergencyGuardian.ZeroAddress.selector);
        new EmergencyGuardian(address(0), pauser);
    }

    function test_T4_03_RevertIf_ConstructorPauserZero() public {
        vm.expectRevert(EmergencyGuardian.ZeroAddress.selector);
        new EmergencyGuardian(admin, address(0));
    }

    function test_T4_04_RevertIf_ConstructorAdminEqualsPauser() public {
        vm.expectRevert(EmergencyGuardian.SameAddress.selector);
        new EmergencyGuardian(admin, admin);
    }

    function test_T4_05_ActivateFreezeSuccessEmitsFullEvent() public {
        bytes32 scope = guardian.SCOPE_GLOBAL();
        string memory reason = "incident";

        vm.warp(1_700_100_000);
        vm.expectEmit(true, false, false, true);
        emit FreezeActivated(scope, reason, block.timestamp, pauser);

        vm.prank(pauser);
        guardian.activateFreeze(scope, reason);

        assertTrue(guardian.isFrozen(scope));
        EmergencyGuardian.FreezeRecord memory rec = guardian.getFreezeRecord(scope);
        assertTrue(rec.active);
        assertEq(rec.activatedAt, block.timestamp);
        assertEq(rec.initiator, pauser);
    }

    function test_T4_06_RevertIf_ActivateFreezeInvalidScope() public {
        vm.prank(pauser);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyGuardian.InvalidScope.selector,
                INVALID_SCOPE
            )
        );
        guardian.activateFreeze(INVALID_SCOPE, "invalid");
    }

    function test_T4_07_RevertIf_ActivateFreezeAlreadyActive() public {
        bytes32 scope = guardian.SCOPE_DISPUTE();
        vm.prank(pauser);
        guardian.activateFreeze(scope, "first");

        vm.prank(pauser);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyGuardian.FreezeAlreadyActive.selector,
                scope
            )
        );
        guardian.activateFreeze(scope, "second");
    }

    function test_T4_08_RevertIf_ActivateFreezeUnauthorized() public {
        bytes32 scope = guardian.SCOPE_GLOBAL();
        vm.prank(attacker);
        // Use general revert to ensure unauthorized access is blocked
        vm.expectRevert(); 
        guardian.activateFreeze(scope, "unauthorized");
    }

    function test_T4_09_DeactivateFreezeSuccessEmitsEventAndSetsActiveFalse() public {
        bytes32 scope = guardian.SCOPE_GLOBAL();
        vm.prank(pauser);
        guardian.activateFreeze(scope, "incident");

        vm.warp(1_700_100_123);
        vm.expectEmit(true, false, false, true);
        emit FreezeDeactivated(scope, block.timestamp, admin);

        vm.prank(admin);
        guardian.deactivateFreeze(scope);

        assertFalse(guardian.isFrozen(scope));
    }

    function test_T4_10_DeactivateFreezePreservesActivatedAtAndInitiator() public {
        bytes32 scope = guardian.SCOPE_MANUAL_REVIEW();

        vm.warp(1_700_100_000);
        vm.prank(pauser);
        guardian.activateFreeze(scope, "manual-review");

        EmergencyGuardian.FreezeRecord memory beforeRec = guardian.getFreezeRecord(scope);
        assertTrue(beforeRec.active);
        assertEq(beforeRec.activatedAt, 1_700_100_000);
        assertEq(beforeRec.initiator, pauser);

        vm.warp(1_700_100_500);
        vm.prank(admin);
        guardian.deactivateFreeze(scope);
        EmergencyGuardian.FreezeRecord memory afterRec = guardian.getFreezeRecord(scope);
        assertFalse(afterRec.active);
        assertEq(afterRec.activatedAt, beforeRec.activatedAt);
        assertEq(afterRec.initiator, beforeRec.initiator);
    }

    function test_T4_11_RevertIf_DeactivateFreezeNotActive() public {
        bytes32 scope = guardian.SCOPE_CREDENTIAL_REVOKED();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyGuardian.FreezeNotActive.selector,
                scope
            )
        );
        guardian.deactivateFreeze(scope);
    }

    function test_T4_12_RevertIf_DeactivateFreezeUnauthorizedIncludingPauser() public {
        bytes32 scope = guardian.SCOPE_DISPUTE();
        vm.prank(pauser);
        guardian.activateFreeze(scope, "dispute");

        vm.prank(pauser);
        // Ensure even a Pauser cannot deactivate a freeze
        vm.expectRevert(); 
        guardian.deactivateFreeze(scope);
    }

    function test_T4_13_IsFrozenCorrectAfterActivateAndDeactivate() public {
        bytes32 scope = guardian.SCOPE_CREDENTIAL_REVOKED();
        assertFalse(guardian.isFrozen(scope));

        vm.prank(pauser);
        guardian.activateFreeze(scope, "credential");
        assertTrue(guardian.isFrozen(scope));

        vm.prank(admin);
        guardian.deactivateFreeze(scope);
        assertFalse(guardian.isFrozen(scope));
    }

    function test_T4_14_GetOverlayPrecedenceNoActiveFreeze() public view {
        (bool active, bytes32 highestScope) = guardian.getOverlayPrecedence();
        assertFalse(active);
        assertEq(highestScope, bytes32(0));
    }

    function test_T4_15_GetOverlayPrecedenceSingleScopeCorrectReturn() public {
        bytes32 scope = guardian.SCOPE_MANUAL_REVIEW();
        vm.prank(pauser);
        guardian.activateFreeze(scope, "manual-review");

        (bool active, bytes32 highestScope) = guardian.getOverlayPrecedence();
        assertTrue(active);
        assertEq(highestScope, scope);
    }

    function test_T4_16_GetOverlayPrecedenceConcurrentScopesHighestWins() public {
        vm.startPrank(pauser);
        guardian.activateFreeze(guardian.SCOPE_CREDENTIAL_REVOKED(), "credential");
        guardian.activateFreeze(guardian.SCOPE_MANUAL_REVIEW(), "manual-review");
        guardian.activateFreeze(guardian.SCOPE_DISPUTE(), "dispute");
        vm.stopPrank();

        (bool active, bytes32 highestScope) = guardian.getOverlayPrecedence();
        assertTrue(active);
        assertEq(highestScope, guardian.SCOPE_DISPUTE());
    }

    function test_T4_17_GlobalOverridesAll() public {
        vm.startPrank(pauser);
        guardian.activateFreeze(guardian.SCOPE_CREDENTIAL_REVOKED(), "credential");
        guardian.activateFreeze(guardian.SCOPE_MANUAL_REVIEW(), "manual-review");
        guardian.activateFreeze(guardian.SCOPE_DISPUTE(), "dispute");
        guardian.activateFreeze(guardian.SCOPE_GLOBAL(), "global");
        vm.stopPrank();

        (bool active, bytes32 highestScope) = guardian.getOverlayPrecedence();
        assertTrue(active);
        assertEq(highestScope, guardian.SCOPE_GLOBAL());
    }

    function test_RevertIf_IsFrozenInvalidScope() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyGuardian.InvalidScope.selector,
                INVALID_SCOPE
            )
        );
        guardian.isFrozen(INVALID_SCOPE);
    }

    function test_RevertIf_GetFreezeRecordInvalidScope() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyGuardian.InvalidScope.selector,
                INVALID_SCOPE
            )
        );
        guardian.getFreezeRecord(INVALID_SCOPE);
    }

    function _scopeFromIndex(uint8 scopeIndex) internal view returns (bytes32) {
        uint8 normalized = scopeIndex % 4;
        if (normalized == 0) return guardian.SCOPE_GLOBAL();
        if (normalized == 1) return guardian.SCOPE_DISPUTE();
        if (normalized == 2) return guardian.SCOPE_MANUAL_REVIEW();
        return guardian.SCOPE_CREDENTIAL_REVOKED();
    }

    function _isCanonicalScopeLocal(bytes32 scope) internal view returns (bool) {
        return scope == guardian.SCOPE_GLOBAL() ||
            scope == guardian.SCOPE_DISPUTE() ||
            scope == guardian.SCOPE_MANUAL_REVIEW() ||
            scope == guardian.SCOPE_CREDENTIAL_REVOKED();
    }
}