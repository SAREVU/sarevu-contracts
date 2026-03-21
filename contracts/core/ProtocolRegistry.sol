// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract ProtocolRegistry is Ownable2Step, Pausable {
    mapping(bytes32 => uint256) private _parameters;
    mapping(bytes32 => uint256) private _minimumFloors;
    mapping(bytes32 => bool) private _parameterExists;

    event ParameterRegistered(bytes32 indexed key, uint256 initialValue, uint256 floor);
    event ParameterSet(bytes32 indexed key, uint256 oldValue, uint256 newValue, address indexed by);
    event FloorUpdated(bytes32 indexed key, uint256 oldFloor, uint256 newFloor);

    error ZeroAddress();
    error ParameterAlreadyExists(bytes32 key);
    error ParameterNotFound(bytes32 key);
    error BelowSafetyFloor(bytes32 key, uint256 value, uint256 floor);
    error InvalidFloor(bytes32 key, uint256 newFloor, uint256 currentValue);

    constructor(address initialOwner) Ownable(msg.sender) {
        if (initialOwner == address(0)) revert ZeroAddress();
        _transferOwnership(initialOwner);
    }

    function registerParameter(bytes32 key, uint256 initialValue, uint256 floor) external onlyOwner {
        if (_parameterExists[key]) revert ParameterAlreadyExists(key);
        if (initialValue < floor) revert BelowSafetyFloor(key, initialValue, floor);

        _parameterExists[key] = true;
        _parameters[key] = initialValue;
        _minimumFloors[key] = floor;

        emit ParameterRegistered(key, initialValue, floor);
    }

    function setParameter(bytes32 key, uint256 value) external onlyOwner whenNotPaused {
        if (!_parameterExists[key]) revert ParameterNotFound(key);

        uint256 floor = _minimumFloors[key];
        if (value < floor) revert BelowSafetyFloor(key, value, floor);

        uint256 oldValue = _parameters[key];
        _parameters[key] = value;

        emit ParameterSet(key, oldValue, value, msg.sender);
    }

    function getParameter(bytes32 key) external view returns (uint256) {
        if (!_parameterExists[key]) revert ParameterNotFound(key);
        return _parameters[key];
    }

    function getFloor(bytes32 key) external view returns (uint256) {
        if (!_parameterExists[key]) revert ParameterNotFound(key);
        return _minimumFloors[key];
    }

    function isBelowFloor(bytes32 key, uint256 value) external view returns (bool) {
        if (!_parameterExists[key]) revert ParameterNotFound(key);
        return value < _minimumFloors[key];
    }

    function parameterExists(bytes32 key) external view returns (bool) {
        return _parameterExists[key];
    }

    function setFloor(bytes32 key, uint256 newFloor) external onlyOwner {
        if (!_parameterExists[key]) revert ParameterNotFound(key);

        uint256 currentValue = _parameters[key];
        if (newFloor > currentValue) revert InvalidFloor(key, newFloor, currentValue);

        uint256 oldFloor = _minimumFloors[key];
        _minimumFloors[key] = newFloor;

        emit FloorUpdated(key, oldFloor, newFloor);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
