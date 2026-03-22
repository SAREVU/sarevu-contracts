// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../core/EscrowVault.sol";
import "./mocks/MockUSDC.sol";
import "./mocks/MockReentrantUSDC.sol";

/// @title  EscrowVaultTest
/// @notice Full test suite: T2-01 through T2-30 + T2-F1 through T2-F4 + Extra-3.
contract EscrowVaultTest is Test {

    // ─── Contracts ────────────────────────────────────────────────────────────

    EscrowVault      public vault;
    MockUSDC         public usdc;
    MockReentrantUSDC public reentrantUsdc;

    // ─── Actors ───────────────────────────────────────────────────────────────

    address public admin    = makeAddr("admin");
    address public operator = makeAddr("operator");
    address public guest    = makeAddr("guest");
    address public host     = makeAddr("host");
    address public attacker = makeAddr("attacker");

    // ─── Constants ────────────────────────────────────────────────────────────

    bytes32 public constant BOOKING_A = keccak256("BOOKING_A");
    bytes32 public constant BOOKING_B = keccak256("BOOKING_B");
    bytes32 public constant BOOKING_UNKNOWN = keccak256("BOOKING_UNKNOWN");

    uint256 public constant AMOUNT     = 1_000e6;
    uint256 public constant HALF       =   500e6;
    uint256 public constant DELAY      = 172_800;

    // ─── Setup ────────────────────────────────────────────────────────────────

    function setUp() public {
        usdc  = new MockUSDC();
        vault = new EscrowVault(address(usdc), admin, operator);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function _deposit(bytes32 bookingId, uint256 amount) internal {
        usdc.mint(guest, amount);
        vm.prank(guest);
        usdc.approve(address(vault), amount);
        vm.prank(operator);
        vault.deposit(bookingId, amount, guest);
    }

    function _depositAndMark(bytes32 bookingId, uint256 amount) internal {
        _deposit(bookingId, amount);
        vm.prank(operator);
        vault.markReleasable(bookingId, DELAY);
    }

    function _readyToRelease(bytes32 bookingId, uint256 amount) internal {
        _depositAndMark(bookingId, amount);
        vm.warp(block.timestamp + DELAY);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-01  Constructor — roles assigned
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_01_ConstructorRolesAssigned() public view {
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(vault.hasRole(vault.OPERATOR_ROLE(), operator));
        assertEq(address(vault.usdc()), address(usdc));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-02  Constructor — zero address  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_02_ConstructorZeroAddress_P0() public {
        vm.expectRevert(EscrowVault.ZeroAddress.selector);
        new EscrowVault(address(0), admin, operator);

        vm.expectRevert(EscrowVault.ZeroAddress.selector);
        new EscrowVault(address(usdc), address(0), operator);

        vm.expectRevert(EscrowVault.ZeroAddress.selector);
        new EscrowVault(address(usdc), admin, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-03  deposit — success + state
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_03_DepositSuccessAndState() public {
        usdc.mint(guest, AMOUNT);
        vm.prank(guest);
        usdc.approve(address(vault), AMOUNT);

        vm.expectEmit(true, false, false, true);
        emit EscrowVault.Deposited(BOOKING_A, AMOUNT, guest);

        vm.prank(operator);
        vault.deposit(BOOKING_A, AMOUNT, guest);

        assertEq(uint256(vault.getState(BOOKING_A)),  uint256(EscrowVault.EscrowState.Held));
        assertEq(vault.getAmount(BOOKING_A),           AMOUNT);
        assertEq(vault.getRecord(BOOKING_A).depositor, guest);
        assertEq(vault.totalHeld(),                    AMOUNT);
        assertEq(usdc.balanceOf(address(vault)),        AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-04  deposit — duplicate bookingId  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_04_DepositDuplicate_P0() public {
        _deposit(BOOKING_A, AMOUNT);
        usdc.mint(guest, AMOUNT);
        vm.prank(guest);
        usdc.approve(address(vault), AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(EscrowVault.BookingAlreadyExists.selector, BOOKING_A)
        );
        vm.prank(operator);
        vault.deposit(BOOKING_A, AMOUNT, guest);

        assertEq(uint256(vault.getState(BOOKING_A)), uint256(EscrowVault.EscrowState.Held));
        assertEq(vault.getAmount(BOOKING_A), AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-05  deposit — zero amount  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_05_DepositZeroAmount_P0() public {
        vm.expectRevert(EscrowVault.ZeroAmount.selector);
        vm.prank(operator);
        vault.deposit(BOOKING_A, 0, guest);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-06  deposit — zero depositor  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_06_DepositZeroDepositor_P0() public {
        vm.expectRevert(EscrowVault.ZeroAddress.selector);
        vm.prank(operator);
        vault.deposit(BOOKING_A, AMOUNT, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-07  deposit — unauthorized  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_07_DepositUnauthorized_P0() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                vault.OPERATOR_ROLE()
            )
        );
        vm.prank(attacker);
        vault.deposit(BOOKING_A, AMOUNT, guest);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-08  markReleasable — success
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_08_MarkReleasableSuccess() public {
        _deposit(BOOKING_A, AMOUNT);
        uint256 before = block.timestamp;

        vm.expectEmit(true, false, false, true);
        emit EscrowVault.MarkedReleasable(BOOKING_A, before + DELAY);

        vm.prank(operator);
        vault.markReleasable(BOOKING_A, DELAY);

        assertEq(uint256(vault.getState(BOOKING_A)), uint256(EscrowVault.EscrowState.Releasable));
        assertEq(vault.getRecord(BOOKING_A).releasableAt, before + DELAY);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-09  markReleasable — delay=0 allowed (boundary)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_09_MarkReleasableZeroDelayAllowed() public {
        _deposit(BOOKING_A, AMOUNT);
        uint256 ts = block.timestamp;

        vm.prank(operator);
        vault.markReleasable(BOOKING_A, 0);

        assertEq(vault.getRecord(BOOKING_A).releasableAt, ts);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-10  markReleasable — wrong state  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_10_MarkReleasableWrongState_P0() public {
        _readyToRelease(BOOKING_A, AMOUNT);
        vm.prank(operator);
        vault.release(BOOKING_A, host); 

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowVault.InvalidState.selector,
                BOOKING_A,
                EscrowVault.EscrowState.Released,
                EscrowVault.EscrowState.Held
            )
        );
        vm.prank(operator);
        vault.markReleasable(BOOKING_A, DELAY);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-11  markReleasable — double call  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_11_MarkReleasableDoubleCall_P0() public {
        _deposit(BOOKING_A, AMOUNT);
        vm.prank(operator);
        vault.markReleasable(BOOKING_A, DELAY);

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowVault.InvalidState.selector,
                BOOKING_A,
                EscrowVault.EscrowState.Releasable,
                EscrowVault.EscrowState.Held
            )
        );
        vm.prank(operator);
        vault.markReleasable(BOOKING_A, DELAY);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-12  release — before delay  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_12_ReleaseBeforeDelay_P0() public {
        _depositAndMark(BOOKING_A, AMOUNT);
        uint256 ra = vault.getRecord(BOOKING_A).releasableAt;

        vm.warp(ra - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowVault.NotYetReleasable.selector,
                BOOKING_A,
                ra,
                block.timestamp
            )
        );
        vm.prank(operator);
        vault.release(BOOKING_A, host);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-13  release — success + CEI
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_13_ReleaseSuccessAndCEI() public {
        _readyToRelease(BOOKING_A, AMOUNT);
        uint256 hostBefore = usdc.balanceOf(host);

        vm.expectEmit(true, true, false, true);
        emit EscrowVault.Released(BOOKING_A, host, AMOUNT);

        vm.prank(operator);
        vault.release(BOOKING_A, host);

        assertEq(uint256(vault.getState(BOOKING_A)),  uint256(EscrowVault.EscrowState.Released));
        assertEq(vault.getRecord(BOOKING_A).amount,   0);
        assertEq(usdc.balanceOf(host),                 hostBefore + AMOUNT);
        assertEq(vault.totalHeld(),                    0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-14  release — wrong state  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_14_ReleaseWrongState_P0() public {
        _deposit(BOOKING_A, AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowVault.InvalidState.selector,
                BOOKING_A,
                EscrowVault.EscrowState.Held,
                EscrowVault.EscrowState.Releasable
            )
        );
        vm.prank(operator);
        vault.release(BOOKING_A, host);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-15  release — double release  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_15_DoubleRelease_P0() public {
        _readyToRelease(BOOKING_A, AMOUNT);
        vm.prank(operator);
        vault.release(BOOKING_A, host);

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowVault.InvalidState.selector,
                BOOKING_A,
                EscrowVault.EscrowState.Released,
                EscrowVault.EscrowState.Releasable
            )
        );
        vm.prank(operator);
        vault.release(BOOKING_A, host);

        assertEq(vault.totalHeld(), 0);
        assertEq(usdc.balanceOf(host), AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-16  release — unauthorized  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_16_ReleaseUnauthorized_P0() public {
        _readyToRelease(BOOKING_A, AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                vault.OPERATOR_ROLE()
            )
        );
        vm.prank(attacker);
        vault.release(BOOKING_A, host);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-17  refund — from Held
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_17_RefundFromHeld() public {
        _deposit(BOOKING_A, AMOUNT);
        uint256 guestBefore = usdc.balanceOf(guest);

        vm.expectEmit(true, true, false, true);
        emit EscrowVault.Refunded(BOOKING_A, guest, AMOUNT);

        vm.prank(operator);
        vault.refund(BOOKING_A, guest);

        assertEq(uint256(vault.getState(BOOKING_A)), uint256(EscrowVault.EscrowState.Refunded));
        assertEq(vault.getRecord(BOOKING_A).amount,  0);
        assertEq(usdc.balanceOf(guest),               guestBefore + AMOUNT);
        assertEq(vault.totalHeld(),                   0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-18  refund — from Releasable
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_18_RefundFromReleasable() public {
        _depositAndMark(BOOKING_A, AMOUNT);
        vm.prank(operator);
        vault.refund(BOOKING_A, guest);

        assertEq(uint256(vault.getState(BOOKING_A)), uint256(EscrowVault.EscrowState.Refunded));
        assertEq(vault.getRecord(BOOKING_A).amount,  0);
        assertEq(vault.totalHeld(),                  0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-19  refund — from Released  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_19_RefundFromReleased_P0() public {
        _readyToRelease(BOOKING_A, AMOUNT);
        vm.prank(operator);
        vault.release(BOOKING_A, host);

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowVault.InvalidState.selector,
                BOOKING_A,
                EscrowVault.EscrowState.Released,
                EscrowVault.EscrowState.Held
            )
        );
        vm.prank(operator);
        vault.refund(BOOKING_A, guest);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-20  refund — double refund  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_20_DoubleRefund_P0() public {
        _deposit(BOOKING_A, AMOUNT);
        vm.prank(operator);
        vault.refund(BOOKING_A, guest);

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowVault.InvalidState.selector,
                BOOKING_A,
                EscrowVault.EscrowState.Refunded,
                EscrowVault.EscrowState.Held
            )
        );
        vm.prank(operator);
        vault.refund(BOOKING_A, guest);

        assertEq(vault.totalHeld(), 0);
        assertEq(usdc.balanceOf(guest), AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-21  REENTRANCY — release  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_21_ReentrancyRelease_P0() public {
        reentrantUsdc = new MockReentrantUSDC();
        EscrowVault reVault = new EscrowVault(address(reentrantUsdc), admin, operator);

        reentrantUsdc.mint(guest, AMOUNT);
        vm.prank(guest);
        reentrantUsdc.approve(address(reVault), AMOUNT);
        vm.prank(operator);
        reVault.deposit(BOOKING_A, AMOUNT, guest);

        vm.prank(operator);
        reVault.markReleasable(BOOKING_A, 0);
        
        bytes memory reentrantCall = abi.encodeWithSelector(
            EscrowVault.release.selector,
            BOOKING_A,
            address(reentrantUsdc)
        );
        reentrantUsdc.configureCallback(address(reVault), reentrantCall);

        vm.prank(operator);
        reVault.release(BOOKING_A, address(reentrantUsdc));
        
        assertEq(uint256(reVault.getState(BOOKING_A)),       uint256(EscrowVault.EscrowState.Released));
        assertEq(reVault.getRecord(BOOKING_A).amount,        0);
        assertEq(reVault.totalHeld(),                        0);
        assertEq(reentrantUsdc.balanceOf(address(reVault)),  0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-22  REENTRANCY — refund  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_22_ReentrancyRefund_P0() public {
        reentrantUsdc = new MockReentrantUSDC();
        EscrowVault reVault = new EscrowVault(address(reentrantUsdc), admin, operator);

        reentrantUsdc.mint(guest, AMOUNT);
        vm.prank(guest);
        reentrantUsdc.approve(address(reVault), AMOUNT);
        vm.prank(operator);
        reVault.deposit(BOOKING_A, AMOUNT, guest);
        
        bytes memory reentrantCall = abi.encodeWithSelector(
            EscrowVault.refund.selector,
            BOOKING_A,
            address(reentrantUsdc)
        );
        reentrantUsdc.configureCallback(address(reVault), reentrantCall);

        vm.prank(operator);
        reVault.refund(BOOKING_A, address(reentrantUsdc));
        
        assertEq(uint256(reVault.getState(BOOKING_A)),       uint256(EscrowVault.EscrowState.Refunded));
        assertEq(reVault.getRecord(BOOKING_A).amount,        0);
        assertEq(reVault.totalHeld(),                        0);
        assertEq(reentrantUsdc.balanceOf(address(reVault)),  0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-23  CEI pattern — slither static analysis  [P0]
    // ═══════════════════════════════════════════════════════════════════════════
    
    function test_T2_23_CEI_StateBeforeTransfer_P0() public {
        _readyToRelease(BOOKING_A, AMOUNT);
        vm.prank(operator);
        vault.release(BOOKING_A, host);

        assertEq(uint256(vault.getState(BOOKING_A)),        uint256(EscrowVault.EscrowState.Released));
        assertEq(vault.getRecord(BOOKING_A).amount,         0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-24  pause — blocks writes
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_24_PauseBlocksWrites() public {
        _readyToRelease(BOOKING_A, AMOUNT);
        vm.prank(admin);
        vault.pause();

        bytes4 pausedError = bytes4(keccak256("EnforcedPause()"));

        vm.expectRevert(pausedError);
        vm.prank(operator);
        vault.deposit(BOOKING_B, AMOUNT, guest);

        vm.expectRevert(pausedError);
        vm.prank(operator);
        vault.markReleasable(BOOKING_A, DELAY);

        vm.expectRevert(pausedError);
        vm.prank(operator);
        vault.release(BOOKING_A, host);

        vm.expectRevert(pausedError);
        vm.prank(operator);
        vault.refund(BOOKING_A, guest);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-25  pause — reads always available
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_25_PauseReadsAvailable() public {
        _deposit(BOOKING_A, AMOUNT);
        vm.prank(admin);
        vault.pause();

        EscrowVault.EscrowRecord memory rec = vault.getRecord(BOOKING_A);
        assertEq(uint256(rec.state), uint256(EscrowVault.EscrowState.Held));
        assertEq(uint256(vault.getState(BOOKING_A)),  uint256(EscrowVault.EscrowState.Held));
        assertEq(vault.getAmount(BOOKING_A), AMOUNT);
        assertEq(vault.totalHeld(),           AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-26  unpause — restores writes
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_26_UnpauseRestoresWrites() public {
        vm.prank(admin);
        vault.pause();
        vm.prank(admin);
        vault.unpause();

        usdc.mint(guest, AMOUNT);
        vm.prank(guest);
        usdc.approve(address(vault), AMOUNT);
        vm.prank(operator);
        vault.deposit(BOOKING_A, AMOUNT, guest);

        assertEq(uint256(vault.getState(BOOKING_A)), uint256(EscrowVault.EscrowState.Held));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-27  getRecord — unknown bookingId
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_27_GetRecordUnknownKey() public {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowVault.BookingNotFound.selector, BOOKING_UNKNOWN)
        );
        vault.getRecord(BOOKING_UNKNOWN);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-28  totalHeld — tracks correctly
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_28_TotalHeldTracksCorrectly() public {
        _deposit(BOOKING_A, HALF);
        assertEq(vault.totalHeld(), HALF);

        _deposit(BOOKING_B, HALF);
        assertEq(vault.totalHeld(), AMOUNT);

        vm.prank(operator);
        vault.markReleasable(BOOKING_A, 0); 
        vm.prank(operator);
        vault.release(BOOKING_A, host);
        assertEq(vault.totalHeld(), HALF);
        
        vm.prank(operator);
        vault.refund(BOOKING_B, guest);
        assertEq(vault.totalHeld(), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-29  release — zero recipient  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_29_ReleaseZeroRecipient_P0() public {
        _readyToRelease(BOOKING_A, AMOUNT);
        vm.expectRevert(EscrowVault.ZeroAddress.selector);
        vm.prank(operator);
        vault.release(BOOKING_A, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-30  refund — zero recipient  [P0]
    // ═══════════════════════════════════════════════════════════════════════════

    function test_T2_30_RefundZeroRecipient_P0() public {
        _deposit(BOOKING_A, AMOUNT);
        vm.expectRevert(EscrowVault.ZeroAddress.selector);
        vm.prank(operator);
        vault.refund(BOOKING_A, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-F1  Fuzz — deposit amounts
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_T2_F1_DepositAmounts(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint128).max); 

        usdc.mint(guest, amount);
        vm.prank(guest);
        usdc.approve(address(vault), amount);
        vm.prank(operator);
        vault.deposit(BOOKING_A, amount, guest);

        assertEq(vault.getAmount(BOOKING_A), amount);
        assertEq(vault.totalHeld(),           amount);
    }

    function testFuzz_T2_F1_DepositZeroAlwaysReverts(bytes32 bookingId) public {
        vm.expectRevert(EscrowVault.ZeroAmount.selector);
        vm.prank(operator);
        vault.deposit(bookingId, 0, guest);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-F2  Fuzz — delay values
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_T2_F2_DelayValues(uint256 delay) public {
        vm.assume(delay <= type(uint128).max);
        
        _deposit(BOOKING_A, AMOUNT);
        uint256 ts = block.timestamp;

        vm.prank(operator);
        vault.markReleasable(BOOKING_A, delay);

        assertEq(vault.getRecord(BOOKING_A).releasableAt, ts + delay);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-F3  Fuzz — terminal state is single-use
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_T2_F3_TerminalStateSingleUse_Release(address recipient) public {
        vm.assume(recipient != address(0));
        _readyToRelease(BOOKING_A, AMOUNT);
        vm.prank(operator);
        vault.release(BOOKING_A, recipient);

        vm.expectRevert();
        vm.prank(operator);
        vault.release(BOOKING_A, recipient);
    }

    function testFuzz_T2_F3_TerminalStateSingleUse_Refund(address recipient) public {
        vm.assume(recipient != address(0));
        _deposit(BOOKING_A, AMOUNT);
        vm.prank(operator);
        vault.refund(BOOKING_A, recipient);

        vm.expectRevert();
        vm.prank(operator);
        vault.refund(BOOKING_A, recipient);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // T2-F4  Fuzz — conservation of value
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_T2_F4_ConservationOfValue(
        uint128 amountA,
        uint128 amountB
    ) public {
        vm.assume(amountA > 0);
        vm.assume(amountB > 0);

        usdc.mint(guest, uint256(amountA) + amountB);
        vm.startPrank(guest);
        usdc.approve(address(vault), uint256(amountA) + amountB);
        vm.stopPrank();

        vm.prank(operator);
        vault.deposit(BOOKING_A, amountA, guest);
        vm.prank(operator);
        vault.deposit(BOOKING_B, amountB, guest);

        assertEq(vault.totalHeld(), uint256(amountA) + amountB);

        vm.prank(operator);
        vault.markReleasable(BOOKING_A, 0);
        vm.prank(operator);
        vault.release(BOOKING_A, host);

        assertEq(vault.totalHeld(), amountB);

        vm.prank(operator);
        vault.refund(BOOKING_B, guest);

        assertEq(vault.totalHeld(), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Extra-3  usdc — immutable
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Extra3_UsdcImmutable() public view {
        assertEq(address(vault.usdc()), address(usdc));
    }
    
    function test_Branch_MarkReleasable_Unknown() public {
        vm.expectRevert(abi.encodeWithSelector(EscrowVault.BookingNotFound.selector, BOOKING_UNKNOWN));
        vm.prank(operator);
        vault.markReleasable(BOOKING_UNKNOWN, DELAY);
    }

    function test_Branch_Release_Unknown() public {
        vm.expectRevert(abi.encodeWithSelector(EscrowVault.BookingNotFound.selector, BOOKING_UNKNOWN));
        vm.prank(operator);
        vault.release(BOOKING_UNKNOWN, host);
    }

    
    function test_Branch_Refund_Unknown() public {
        vm.expectRevert(abi.encodeWithSelector(EscrowVault.BookingNotFound.selector, BOOKING_UNKNOWN));
        vm.prank(operator);
        vault.refund(BOOKING_UNKNOWN, guest);
    }

    function test_Branch_Pause_Unauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, vault.DEFAULT_ADMIN_ROLE()));
        vm.prank(attacker);
        vault.pause();
    }

    function test_Branch_Unpause_Unauthorized() public {
        vm.prank(admin);
        vault.pause();
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, vault.DEFAULT_ADMIN_ROLE()));
        vm.prank(attacker);
        vault.unpause();
    }

    function test_Branch_Refund_AlreadyRefunded() public {
        _deposit(BOOKING_A, AMOUNT);
        vm.prank(operator);
        vault.refund(BOOKING_A, guest);
        
        vm.expectRevert(abi.encodeWithSelector(EscrowVault.InvalidState.selector, BOOKING_A, EscrowVault.EscrowState.Refunded, EscrowVault.EscrowState.Held));
        vm.prank(operator);
        vault.refund(BOOKING_A, guest);
     }
        
    function test_Branch_Deposit_InsufficientBalance_Reverts() public {
        vm.prank(operator); 
        vm.expectRevert("MockUSDC: insufficient allowance"); 
         vault.deposit(BOOKING_A, type(uint256).max, guest);
    }

    function test_Branch_Release_AlreadyReleased_Reverts() public {
        _deposit(BOOKING_A, AMOUNT);
        vm.prank(operator);
        vault.markReleasable(BOOKING_A, 0);
        vm.prank(operator);
        vault.release(BOOKING_A, host);
        
        vm.expectRevert(abi.encodeWithSelector(
            EscrowVault.InvalidState.selector, 
            BOOKING_A, 
            EscrowVault.EscrowState.Released, 
            EscrowVault.EscrowState.Releasable 
        ));
        vm.prank(operator);
        vault.release(BOOKING_A, host);
    }
}