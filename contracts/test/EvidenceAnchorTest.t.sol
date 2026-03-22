// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {EvidenceAnchor} from "../core/EvidenceAnchor.sol";

/**
 * @title EvidenceAnchorTest
 * @dev Full test suite to achieve 100% coverage for EvidenceAnchor.sol
 * Strictly following Canonical Spec v1.1 standards.
 */
contract EvidenceAnchorTest is Test {
    EvidenceAnchor internal evidenceAnchor;

    address internal admin = makeAddr("admin");
    address internal anchorService = makeAddr("anchorService");
    address internal attacker = makeAddr("attacker");

    bytes32 internal constant BOOKING_ID = keccak256("booking-1");
    bytes32 internal constant CONTENT_HASH = keccak256("content-1");
    uint256 internal constant TIMELINE_ANCHOR_ID = 1;

    event EvidenceAnchored(
        bytes32 indexed bookingId,
        bytes32 indexed contentHash,
        uint256 timelineAnchorId,
        address indexed submitter,
        uint256 timestamp
    );

    function setUp() public {
        evidenceAnchor = new EvidenceAnchor(admin, anchorService);
    }

    // --- Constructor Tests ---

    function test_Constructor_SetsRolesCorrectly() public view {
        assertTrue(evidenceAnchor.hasRole(evidenceAnchor.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(evidenceAnchor.hasRole(evidenceAnchor.ANCHOR_ROLE(), anchorService));
        assertFalse(evidenceAnchor.hasRole(evidenceAnchor.ANCHOR_ROLE(), attacker));
    }

    function test_RevertIf_ConstructorAdminIsZero() public {
        vm.expectRevert(EvidenceAnchor.ZeroAddress.selector);
        new EvidenceAnchor(address(0), anchorService);
    }

    function test_RevertIf_ConstructorAnchorIsZero() public {
        vm.expectRevert(EvidenceAnchor.ZeroAddress.selector);
        new EvidenceAnchor(admin, address(0));
    }

    // --- Access Control & Validation Reverts ---

    function test_RevertIf_UnauthorizedCaller() public {
        bytes32 role = evidenceAnchor.ANCHOR_ROLE();
        vm.prank(attacker);
        // Matching exact error with arguments: (account, role)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                role
            )
        );
        evidenceAnchor.anchor(BOOKING_ID, CONTENT_HASH, TIMELINE_ANCHOR_ID);
    }

    function test_RevertIf_BookingIdIsZero() public {
        vm.prank(anchorService);
        vm.expectRevert(EvidenceAnchor.ZeroBookingId.selector);
        evidenceAnchor.anchor(bytes32(0), CONTENT_HASH, TIMELINE_ANCHOR_ID);
    }

    function test_RevertIf_ContentHashIsZero() public {
        vm.prank(anchorService);
        vm.expectRevert(EvidenceAnchor.ZeroContentHash.selector);
        evidenceAnchor.anchor(BOOKING_ID, bytes32(0), TIMELINE_ANCHOR_ID);
    }

    function test_RevertIf_TimelineAnchorIdIsZero() public {
        vm.prank(anchorService);
        vm.expectRevert(EvidenceAnchor.ZeroTimelineAnchorId.selector);
        evidenceAnchor.anchor(BOOKING_ID, CONTENT_HASH, 0);
    }

    // --- Functional Tests ---

    function test_Anchor_Success_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit EvidenceAnchored(BOOKING_ID, CONTENT_HASH, TIMELINE_ANCHOR_ID, anchorService, block.timestamp);
        
        vm.prank(anchorService);
        evidenceAnchor.anchor(BOOKING_ID, CONTENT_HASH, TIMELINE_ANCHOR_ID);
    }

    function test_Getters_ReturnCorrectData() public {
        vm.startPrank(anchorService);
        evidenceAnchor.anchor(BOOKING_ID, CONTENT_HASH, TIMELINE_ANCHOR_ID);
        bytes32 secondHash = keccak256("content-2");
        evidenceAnchor.anchor(BOOKING_ID, secondHash, 2);
        vm.stopPrank();

        // Test getEvidence (single record)
        EvidenceAnchor.EvidenceRecord memory record = evidenceAnchor.getEvidence(BOOKING_ID, 0);
        assertEq(record.contentHash, CONTENT_HASH);
        assertEq(record.timelineAnchorId, TIMELINE_ANCHOR_ID);
        assertEq(record.submitter, anchorService);

        // Test getAllEvidence (array)
        EvidenceAnchor.EvidenceRecord[] memory all = evidenceAnchor.getAllEvidence(BOOKING_ID);
        assertEq(all.length, 2);
        assertEq(all[1].contentHash, secondHash);

        // Test getEvidenceCount
        assertEq(evidenceAnchor.getEvidenceCount(BOOKING_ID), 2);

        // Test totalAnchored (global counter)
        assertEq(evidenceAnchor.totalAnchored(), 2);
    }

    function test_NoUpdateOrDelete_FailsLowLevel() public {
        // Simulate calls to non-existent functions to confirm append-only status
        (bool ok1,) = address(evidenceAnchor).call(abi.encodeWithSignature("updateEvidence()"));
        (bool ok2,) = address(evidenceAnchor).call(abi.encodeWithSignature("deleteEvidence()"));
        assertFalse(ok1);
        assertFalse(ok2);
    }

    // --- Fuzzing ---

    function testFuzz_AuthorizedValidInputsAlwaysAnchor(
        bytes32 bookingId,
        bytes32 contentHash,
        uint256 timelineAnchorId
    ) public {
        vm.assume(bookingId != bytes32(0));
        vm.assume(contentHash != bytes32(0));
        vm.assume(timelineAnchorId > 0);

        vm.prank(anchorService);
        evidenceAnchor.anchor(bookingId, contentHash, timelineAnchorId);
        
        assertEq(evidenceAnchor.getEvidenceCount(bookingId), 1);
        assertEq(evidenceAnchor.totalAnchored(), 1);
    }
}