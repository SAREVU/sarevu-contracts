// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract EmergencyGuardian is AccessControl {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SCOPE_GLOBAL = keccak256("GLOBAL");
    bytes32 public constant SCOPE_DISPUTE = keccak256("DISPUTE");
    bytes32 public constant SCOPE_MANUAL_REVIEW = keccak256("MANUAL_REVIEW");
    bytes32 public constant SCOPE_CREDENTIAL_REVOKED = keccak256("CREDENTIAL_REVOKED");

    struct FreezeRecord {
        bool active;
        uint256 activatedAt;
        address initiator;
    }

    mapping(bytes32 => FreezeRecord) private _freezes;

    error ZeroAddress();
    error SameAddress();
    error InvalidScope(bytes32 scope);
    error FreezeAlreadyActive(bytes32 scope);
    error FreezeNotActive(bytes32 scope);

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

    constructor(address admin, address pauser) {
        if (admin == address(0)) revert ZeroAddress();
        if (pauser == address(0)) revert ZeroAddress();
        if (admin == pauser) revert SameAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
    }

    function activateFreeze(bytes32 scope, string calldata reason)
        external
        onlyRole(PAUSER_ROLE)
    {
        if (!_isCanonicalScope(scope)) revert InvalidScope(scope);
        FreezeRecord storage rec = _freezes[scope];
        if (rec.active) revert FreezeAlreadyActive(scope);

        rec.active = true;
        rec.activatedAt = block.timestamp;
        rec.initiator = msg.sender;

        emit FreezeActivated(scope, reason, block.timestamp, msg.sender);
    }

    function deactivateFreeze(bytes32 scope)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (!_isCanonicalScope(scope)) revert InvalidScope(scope);
        FreezeRecord storage rec = _freezes[scope];
        if (!rec.active) revert FreezeNotActive(scope);

        rec.active = false;

        emit FreezeDeactivated(scope, block.timestamp, msg.sender);
    }

    function isFrozen(bytes32 scope) external view returns (bool) {
        if (!_isCanonicalScope(scope)) revert InvalidScope(scope);
        return _freezes[scope].active;
    }

    function getOverlayPrecedence()
        external
        view
        returns (bool active, bytes32 highestScope)
    {
        if (_freezes[SCOPE_GLOBAL].active) return (true, SCOPE_GLOBAL);
        if (_freezes[SCOPE_DISPUTE].active) return (true, SCOPE_DISPUTE);
        if (_freezes[SCOPE_MANUAL_REVIEW].active) return (true, SCOPE_MANUAL_REVIEW);
        if (_freezes[SCOPE_CREDENTIAL_REVOKED].active) return (true, SCOPE_CREDENTIAL_REVOKED);
        return (false, bytes32(0));
    }

    function getFreezeRecord(bytes32 scope)
        external
        view
        returns (FreezeRecord memory)
    {
        if (!_isCanonicalScope(scope)) revert InvalidScope(scope);
        return _freezes[scope];
    }

    function _isCanonicalScope(bytes32 scope) private pure returns (bool) {
        return scope == SCOPE_GLOBAL ||
            scope == SCOPE_DISPUTE ||
            scope == SCOPE_MANUAL_REVIEW ||
            scope == SCOPE_CREDENTIAL_REVOKED;
    }
}