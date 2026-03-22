// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockUSDC.sol";

/// @title  MockReentrantUSDC
/// @notice ERC-20 mock that fires an arbitrary callback during transfer().
contract MockReentrantUSDC is MockUSDC {

    address public callbackTarget;
    bytes   public callbackData;

    bool private _callbackEnabled;
    bool private _inCallback;

    function configureCallback(address target, bytes calldata data) external {
        callbackTarget   = target;
        callbackData     = data;
        _callbackEnabled = true;
    }

    function clearCallback() external {
        callbackTarget   = address(0);
        callbackData     = "";
        _callbackEnabled = false;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        bool ok = super.transfer(to, amount);
        if (_callbackEnabled && !_inCallback && callbackTarget != address(0)) {
            _inCallback = true;
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = callbackTarget.call(callbackData);
            (success);
            _inCallback = false;
        }

        return ok;
    }
}