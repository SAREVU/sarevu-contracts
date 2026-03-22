// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title EvidenceAnchor
/// @notice Canonical Spec v1.1 Implementation
contract EvidenceAnchor is AccessControl {
    bytes32 public constant ANCHOR_ROLE = keccak256("ANCHOR_ROLE");

    struct EvidenceRecord {
        bytes32 contentHash;
        uint256 timelineAnchorId;
        address submitter;
        uint256 timestamp;
    }

    error ZeroAddress();
    error ZeroBookingId();
    error ZeroContentHash();
    error ZeroTimelineAnchorId();

    event EvidenceAnchored(
        bytes32 indexed bookingId,
        bytes32 indexed contentHash,
        uint256 timelineAnchorId,
        address indexed submitter,
        uint256 timestamp
    );

    mapping(bytes32 => EvidenceRecord[]) private _evidence;
    uint256 private _totalAnchored;

    constructor(address admin, address anchorRole) {
        if (admin == address(0) || anchorRole == address(0)) {
            revert ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ANCHOR_ROLE, anchorRole);
    }

    function anchor(
        bytes32 bookingId,
        bytes32 contentHash,
        uint256 timelineAnchorId
    ) external onlyRole(ANCHOR_ROLE) {
        if (bookingId == bytes32(0)) revert ZeroBookingId();
        if (contentHash == bytes32(0)) revert ZeroContentHash();
        if (timelineAnchorId == 0) revert ZeroTimelineAnchorId();

        EvidenceRecord memory record = EvidenceRecord({
            contentHash: contentHash,
            timelineAnchorId: timelineAnchorId,
            submitter: msg.sender,
            timestamp: block.timestamp
        });

        _evidence[bookingId].push(record);
        
        unchecked {
            ++_totalAnchored;
        }

        emit EvidenceAnchored(
            bookingId,
            contentHash,
            timelineAnchorId,
            msg.sender,
            block.timestamp
        );
    }

    function getEvidence(bytes32 bookingId, uint256 index)
        external
        view
        returns (EvidenceRecord memory)
    {
        return _evidence[bookingId][index];
    }

    function getAllEvidence(bytes32 bookingId)
        external
        view
        returns (EvidenceRecord[] memory)
    {
        return _evidence[bookingId];
    }

    function getEvidenceCount(bytes32 bookingId)
        external
        view
        returns (uint256)
    {
        return _evidence[bookingId].length;
    }

    function totalAnchored() external view returns (uint256) {
        return _totalAnchored;
    }
}