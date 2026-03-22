// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {EmergencyGuardian} from "../core/EmergencyGuardian.sol";

contract DeployEmergencyGuardian is Script {
    function run() external returns (EmergencyGuardian deployed) {
        // Отримання приватного ключа та адрес із файлу .env
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("MULTISIG_SAFE_ADDRESS");
        address pauser = vm.envAddress("PAUSER_ADDRESS");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Деплой контракту
        deployed = new EmergencyGuardian(admin, pauser);

        vm.stopBroadcast();

        // Пост-деплой перевірки (Post-deploy checks)
        require(
            deployed.hasRole(deployed.DEFAULT_ADMIN_ROLE(), admin),
            "DeployEmergencyGuardian: admin role verification failed"
        );
        require(
            deployed.hasRole(deployed.PAUSER_ROLE(), pauser),
            "DeployEmergencyGuardian: pauser role verification failed"
        );
        require(
            !deployed.hasRole(deployed.DEFAULT_ADMIN_ROLE(), deployer),
            "DeployEmergencyGuardian: deployer must not be admin"
        );
        require(
            !deployed.hasRole(deployed.PAUSER_ROLE(), admin),
            "DeployEmergencyGuardian: admin must not have pauser role"
        );
        require(
            !deployed.hasRole(deployed.DEFAULT_ADMIN_ROLE(), pauser),
            "DeployEmergencyGuardian: pauser must not have admin role"
        );

        console2.log("EmergencyGuardian deployed at:", address(deployed));
        console2.log("Admin:", admin);
        console2.log("Pauser:", pauser);
    }
}