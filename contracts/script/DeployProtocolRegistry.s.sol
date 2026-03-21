// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../core/ProtocolRegistry.sol";

contract DeployProtocolRegistry is Script {
    function run() external {
        address multisig = vm.envAddress("MULTISIG_SAFE_ADDRESS");
        require(multisig != address(0), "MULTISIG_SAFE_ADDRESS not set");

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        ProtocolRegistry registry = new ProtocolRegistry(multisig);

        registry.registerParameter(keccak256("BOOKING_COOLDOWN"), 86400, 3600);
        registry.registerParameter(keccak256("DISPUTE_WINDOW"), 604800, 86400);
        registry.registerParameter(keccak256("PAYOUT_DELAY"), 172800, 3600);
        registry.registerParameter(keccak256("EVIDENCE_WINDOW"), 259200, 43200);
        registry.registerParameter(keccak256("TIMELOCK_STANDARD"), 172800, 3600);
        registry.registerParameter(keccak256("TIMELOCK_CRITICAL"), 259200, 172800);

        vm.stopBroadcast();

        console.log("ProtocolRegistry deployed:", address(registry));
        console.log("Owner (multisig):", registry.owner());
    }
}
