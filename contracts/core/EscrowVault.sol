// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // OZ v5
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/// @title  EscrowVault
/// @notice USDC-only escrow for Sarevu bookings.
contract EscrowVault is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    IERC20 public immutable usdc;
    uint256 private _totalHeld;

    enum EscrowState { None, Held, Releasable, Released, Refunded }

    struct EscrowRecord {
        EscrowState state;
        uint256     amount;
        address     depositor;
        uint256     depositedAt;
        uint256     releasableAt;
    }

    mapping(bytes32 => EscrowRecord) private _escrows;

    event Deposited(bytes32 indexed bookingId, uint256 amount, address indexed depositor);
    event MarkedReleasable(bytes32 indexed bookingId, uint256 releasableAt);
    event Released(bytes32 indexed bookingId, address indexed recipient, uint256 amount);
    event Refunded(bytes32 indexed bookingId, address indexed recipient, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error BookingAlreadyExists(bytes32 bookingId);
    error BookingNotFound(bytes32 bookingId);
    error InvalidState(bytes32 bookingId, EscrowState current, EscrowState required);
    error NotYetReleasable(bytes32 bookingId, uint256 releasableAt, uint256 currentTime);

    constructor(address _usdc, address admin, address operator) {
        if (_usdc    == address(0)) revert ZeroAddress();
        if (admin    == address(0)) revert ZeroAddress();
        if (operator == address(0)) revert ZeroAddress();

        usdc = IERC20(_usdc);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);
    }

    function deposit(bytes32 bookingId, uint256 amount, address depositor) external nonReentrant onlyRole(OPERATOR_ROLE) whenNotPaused {
        if (amount    == 0)         revert ZeroAmount();
        if (depositor == address(0)) revert ZeroAddress();
        if (_escrows[bookingId].state != EscrowState.None) revert BookingAlreadyExists(bookingId);

        _escrows[bookingId] = EscrowRecord({
            state:       EscrowState.Held,
            amount:      amount,
            depositor:   depositor,
            depositedAt: block.timestamp,
            releasableAt: 0
        });
        _totalHeld += amount;

        usdc.safeTransferFrom(depositor, address(this), amount);
        emit Deposited(bookingId, amount, depositor);
    }

    function markReleasable(bytes32 bookingId, uint256 delay) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        EscrowRecord storage record = _escrows[bookingId];
        if (record.state == EscrowState.None) revert BookingNotFound(bookingId);
        if (record.state != EscrowState.Held) revert InvalidState(bookingId, record.state, EscrowState.Held);

        record.state        = EscrowState.Releasable;
        record.releasableAt = block.timestamp + delay;
        emit MarkedReleasable(bookingId, record.releasableAt);
    }

    function release(bytes32 bookingId, address recipient) external nonReentrant onlyRole(OPERATOR_ROLE) whenNotPaused {
        if (recipient == address(0)) revert ZeroAddress();
        EscrowRecord storage record = _escrows[bookingId];

        if (record.state == EscrowState.None) revert BookingNotFound(bookingId);
        if (record.state != EscrowState.Releasable) revert InvalidState(bookingId, record.state, EscrowState.Releasable);
        if (block.timestamp < record.releasableAt) revert NotYetReleasable(bookingId, record.releasableAt, block.timestamp);

        uint256 amount = record.amount;
        record.state  = EscrowState.Released;
        record.amount = 0;
        _totalHeld   -= amount;

        usdc.safeTransfer(recipient, amount);
        emit Released(bookingId, recipient, amount);
    }

    function refund(bytes32 bookingId, address recipient) external nonReentrant onlyRole(OPERATOR_ROLE) whenNotPaused {
        if (recipient == address(0)) revert ZeroAddress();
        EscrowRecord storage record = _escrows[bookingId];

        if (record.state == EscrowState.None) revert BookingNotFound(bookingId);
        if (record.state != EscrowState.Held && record.state != EscrowState.Releasable) revert InvalidState(bookingId, record.state, EscrowState.Held);

        uint256 amount = record.amount;
        record.state  = EscrowState.Refunded;
        record.amount = 0;
        _totalHeld   -= amount;

        usdc.safeTransfer(recipient, amount);
        emit Refunded(bookingId, recipient, amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }

    function getRecord(bytes32 bookingId) external view returns (EscrowRecord memory) {
        if (_escrows[bookingId].state == EscrowState.None) revert BookingNotFound(bookingId);
        return _escrows[bookingId];
    }

    function getState(bytes32 bookingId) external view returns (EscrowState) {
        if (_escrows[bookingId].state == EscrowState.None) revert BookingNotFound(bookingId);
        return _escrows[bookingId].state;
    }

    function getAmount(bytes32 bookingId) external view returns (uint256) {
        if (_escrows[bookingId].state == EscrowState.None) revert BookingNotFound(bookingId);
        return _escrows[bookingId].amount;
    }

    function totalHeld() external view returns (uint256) { return _totalHeld; }
}
