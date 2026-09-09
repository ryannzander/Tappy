// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TappyGate} from "../src/TappyGate.sol";
import {MockToken} from "../src/MockToken.sol";
import {MockSwap} from "../src/MockSwap.sol";

/// @notice Deploys the whole demo world and writes addresses to deployments/<chain>.json.
/// @dev Required env: DEPLOYER_KEY, AGENT_ADDRESS, CHAIN_KEY, and at least one human authority.
///      Human authorities: HUMAN_K1_ADDRESS (the Flipper, secp256k1) and/or HUMAN_QX + HUMAN_QY
///      (the iPhone's Secure Enclave key, P-256). Configure both to demo either device.
///      Optional: GATE_FUNDING_WEI (default 0.05e18), P256_VERIFIER (default 0x100).
///      Re-run freely; addresses in git are the source of truth for the apps.
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address agent = vm.envAddress("AGENT_ADDRESS");
        string memory chainKey = vm.envString("CHAIN_KEY");
        uint256 funding = vm.envOr("GATE_FUNDING_WEI", uint256(0.05 ether));

        address humanK1 = vm.envOr("HUMAN_K1_ADDRESS", address(0));
        bytes32 humanQx = vm.envOr("HUMAN_QX", bytes32(0));
        bytes32 humanQy = vm.envOr("HUMAN_QY", bytes32(0));
        // EIP-7951 lives at 0x100 on Sepolia (verified, docs/spikes.md #5). Chains without it
        // need a deployed verifier address here instead — the gate's staticcall is identical.
        address p256Verifier = vm.envOr("P256_VERIFIER", address(0x100));

        require(humanK1 != address(0) || humanQx != bytes32(0), "set HUMAN_K1_ADDRESS or HUMAN_QX/QY");

        vm.startBroadcast(deployerKey);

        TappyGate gate = new TappyGate(agent, humanK1, humanQx, humanQy, p256Verifier);
        MockToken token = new MockToken();
        MockSwap swap = new MockSwap(token);

        if (funding > 0) {
            (bool ok,) = address(gate).call{value: funding}("");
            require(ok, "funding the gate failed");
        }

        vm.stopBroadcast();

        console2.log("gate     ", address(gate));
        console2.log("token    ", address(token));
        console2.log("swap     ", address(swap));

        string memory obj = "deployment";
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeAddress(obj, "gate", address(gate));
        vm.serializeAddress(obj, "token", address(token));
        vm.serializeAddress(obj, "swap", address(swap));
        vm.serializeAddress(obj, "agent", agent);
        vm.serializeAddress(obj, "humanK1", humanK1);
        vm.serializeBytes32(obj, "humanQx", humanQx);
        vm.serializeBytes32(obj, "humanQy", humanQy);
        string memory json = vm.serializeAddress(obj, "p256Verifier", p256Verifier);
        vm.writeJson(json, string.concat("./deployments/", chainKey, ".json"));
    }
}
