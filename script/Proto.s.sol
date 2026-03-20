// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

/// @notice Base script for deploying protofactory contracts via Nick's CREATE2 deployer with salt 0x0.
/// @dev Subclasses provide the contract name and creation code.
///      The predicted address is written to io/$env/$chain/$name.json.
abstract contract ProtoScript is Script {
    address constant NICK = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function name() internal pure virtual returns (string memory);
    function creationCode() internal pure virtual returns (bytes memory);

    function run() external {
        string memory n = name();
        bytes memory code = creationCode();

        console2.log("script   :", n);
        address predicted = vm.computeCreate2Address(0x0, keccak256(code));
        console2.log("predicted:", predicted);
        if (predicted.code.length == 0) {
            vm.startBroadcast();
            (bool ok, ) = NICK.call(abi.encodePacked(bytes32(0), code));
            vm.stopBroadcast();
            require(ok, "create2 failed");
            console2.log("actual   :", predicted);
        } else {
            console2.log("already deployed");
        }

        string memory dir = string.concat("io/", vm.envString("env"), "/", vm.envString("chain"));
        string memory path = string.concat(dir, "/", n, ".json");
        vm.createDir(dir, true);
        vm.writeJson(vm.toString(predicted), path);
    }
}
