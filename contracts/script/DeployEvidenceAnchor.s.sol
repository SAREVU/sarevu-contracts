// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {EvidenceAnchor} from "../core/EvidenceAnchor.sol";

contract DeployEvidenceAnchor is Script {
    function run() external returns (EvidenceAnchor deployed) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("MULTISIG_SAFE_ADDRESS");
        address anchorRole = vm.envAddress("ANCHOR_ROLE_ADDRESS");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        deployed = new EvidenceAnchor(admin, anchorRole);
        vm.stopBroadcast();

        require(deployed.hasRole(deployed.DEFAULT_ADMIN_ROLE(), admin), "Admin role failed");
        require(deployed.hasRole(deployed.ANCHOR_ROLE(), anchorRole), "Anchor role failed");
        require(!deployed.hasRole(deployed.DEFAULT_ADMIN_ROLE(), deployer), "Deployer must not be admin");

        console2.log("EvidenceAnchor deployed at:", address(deployed));
    }
}