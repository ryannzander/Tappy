// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TappyGate} from "../src/TappyGate.sol";
import {P256Verifier} from "p256-verifier/P256Verifier.sol";

/// @notice The iPhone half of the 2-of-2. The Secure Enclave can only sign P-256, and it
///         hashes with SHA-256 before signing, so the gate verifies sha256(digest).
///         Pinned by the frozen vector so Solidity, TypeScript and Swift cannot drift.
/// @dev Runs against the vendored Solidity verifier rather than the 0x100 precompile, so the
///      suite passes on any Foundry build. `test_fork_precompile_accepts_the_vector` covers
///      the precompile itself.
contract TappyGateP256Test is Test {
    string constant VECTOR = "../protocol/vectors/p256.json";
    address constant PINNED_GATE = 0x1111111111111111111111111111111111111111;

    TappyGate gate;
    address verifier;
    address agent;
    uint256 agentKey;

    bytes32 qx;
    bytes32 qy;
    bytes sig64;
    bytes sig64HighS;

    function setUp() public {
        verifier = address(new P256Verifier());

        string memory json = vm.readFile(VECTOR);
        qx = vm.parseJsonBytes32(json, ".qx");
        qy = vm.parseJsonBytes32(json, ".qy");
        sig64 = vm.parseJsonBytes(json, ".signature64");
        sig64HighS = vm.parseJsonBytes(json, ".signature64HighS");

        (agent, agentKey) = makeAddrAndKey("agent");
        gate = new TappyGate(agent, address(0), qx, qy, verifier);
        vm.deal(address(gate), 1 ether);
    }

    /// The vector signs the digest from execute.json, so reproduce that exact call.
    function _vectorCall()
        internal
        pure
        returns (address to, uint256 value, bytes memory data, uint256 deadline)
    {
        return (0x2222222222222222222222222222222222222222, 0.01 ether, "", 2000000000);
    }

    function _agentSig(bytes32 digest) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(agentKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev The vector's digest is bound to chainId 11155111 and gate 0x1111…1111, so the gate
    ///      under test has to answer to both. OpenZeppelin's EIP712 rebuilds the domain
    ///      separator whenever address(this) differs from the one cached at construction, which
    ///      is what makes the etched copy produce the pinned digest. Digest.t.sol does the same.
    function _pinnedGate(bytes32 useQx) internal returns (TappyGate) {
        vm.chainId(11155111);
        TappyGate fresh = new TappyGate(agent, address(0), useQx, qy, verifier);
        // immutables live in code, so the etched copy keeps agent/qx/qy/verifier
        vm.etch(PINNED_GATE, address(fresh).code);
        vm.deal(PINNED_GATE, 1 ether);
        return TappyGate(payable(PINNED_GATE));
    }

    function _pinnedGate() internal returns (TappyGate) {
        return _pinnedGate(qx);
    }

    /// @dev Isolates the crypto from the digest: if this fails the vector and the verifier
    ///      disagree, and no amount of staring at execute() will help.
    function test_the_verifier_accepts_the_frozen_vector_directly() public view {
        string memory json = vm.readFile(VECTOR);
        bytes32 message = vm.parseJsonBytes32(json, ".messageSha256");
        bytes32 digest = vm.parseJsonBytes32(json, ".digest");

        assertEq(sha256(abi.encodePacked(digest)), message, "messageSha256 != sha256(digest)");

        (bool ok, bytes memory ret) = verifier.staticcall(abi.encodePacked(message, sig64, qx, qy));
        assertTrue(ok && bytes32(ret) == bytes32(uint256(1)), "verifier rejected the frozen vector");
    }

    function test_p256_signature_from_the_vector_executes() public {
        TappyGate g = _pinnedGate();
        (address to, uint256 value, bytes memory data, uint256 deadline) = _vectorCall();
        bytes32 digest = g.digestOf(0, to, value, data, deadline);

        vm.warp(deadline - 1);
        g.execute(to, value, data, deadline, _agentSig(digest), sig64);

        assertEq(g.nonce(), 1, "nonce consumed");
        assertEq(to.balance, value, "value moved");
    }

    function test_high_s_p256_signature_is_accepted() public {
        TappyGate g = _pinnedGate();
        (address to, uint256 value, bytes memory data, uint256 deadline) = _vectorCall();
        bytes32 digest = g.digestOf(0, to, value, data, deadline);

        vm.warp(deadline - 1);
        // EIP-7951 does not require low-s, and neither do we: the nonce makes replay moot.
        g.execute(to, value, data, deadline, _agentSig(digest), sig64HighS);
        assertEq(g.nonce(), 1);
    }

    function test_replaying_a_p256_signature_reverts() public {
        TappyGate g = _pinnedGate();
        (address to, uint256 value, bytes memory data, uint256 deadline) = _vectorCall();
        bytes32 digest = g.digestOf(0, to, value, data, deadline);
        bytes memory aSig = _agentSig(digest);

        vm.warp(deadline - 1);
        g.execute(to, value, data, deadline, aSig, sig64);

        vm.expectRevert(TappyGate.BadAgentSig.selector); // nonce moved, so the digest changed
        g.execute(to, value, data, deadline, aSig, sig64);
    }

    function test_wrong_public_key_reverts() public {
        TappyGate g = _pinnedGate(bytes32(uint256(qx) ^ 1));
        (address to, uint256 value, bytes memory data, uint256 deadline) = _vectorCall();
        bytes32 digest = g.digestOf(0, to, value, data, deadline);

        vm.warp(deadline - 1);
        vm.expectRevert(TappyGate.BadHumanSig.selector);
        g.execute(to, value, data, deadline, _agentSig(digest), sig64);
    }

    function test_a_signature_of_any_other_length_reverts() public {
        (address to, uint256 value, bytes memory data, uint256 deadline) = _vectorCall();
        bytes32 digest = gate.digestOf(0, to, value, data, deadline);

        vm.warp(deadline - 1);
        vm.expectRevert(TappyGate.BadHumanSigLength.selector);
        gate.execute(to, value, data, deadline, _agentSig(digest), hex"1234");
    }

    function test_secp256k1_signature_rejected_when_no_k1_human_configured() public {
        (address to, uint256 value, bytes memory data, uint256 deadline) = _vectorCall();
        bytes32 digest = gate.digestOf(0, to, value, data, deadline);

        vm.warp(deadline - 1);
        vm.expectRevert(TappyGate.NoK1Human.selector);
        gate.execute(to, value, data, deadline, _agentSig(digest), _agentSig(digest));
    }

    /// @dev The mirror of the test above: a Flipper-only gate must reject a phone signature
    ///      by name, not by falling through to a staticcall against an unset verifier.
    function test_p256_signature_rejected_when_no_p256_human_configured() public {
        TappyGate k1Only = new TappyGate(agent, makeAddr("human"), bytes32(0), bytes32(0), address(0));
        vm.deal(address(k1Only), 1 ether);

        (address to, uint256 value, bytes memory data, uint256 deadline) = _vectorCall();
        bytes32 digest = k1Only.digestOf(0, to, value, data, deadline);

        vm.warp(deadline - 1);
        vm.expectRevert(TappyGate.NoP256Human.selector);
        k1Only.execute(to, value, data, deadline, _agentSig(digest), sig64);
    }

    function test_constructor_with_no_human_authority_reverts() public {
        vm.expectRevert(TappyGate.NoHumanAuthority.selector);
        new TappyGate(agent, address(0), bytes32(0), bytes32(0), verifier);
    }

    /// @notice Proves the frozen vector also satisfies the real EIP-7951 precompile, not just the
    ///         Solidity verifier the other tests use. Skipped unless SEPOLIA_RPC_URL is set.
    /// @dev Deliberately `vm.rpc`, not `vm.createSelectFork` + staticcall. A fork runs the call in
    ///      Foundry's own EVM at this project's evm_version (cancun, the newest solc 0.8.24
    ///      accepts), which has no precompile at 0x100 — so a fork would report "rejected" while
    ///      Sepolia says otherwise. Only a real eth_call answers the question being asked.
    function test_sepolia_precompile_accepts_the_vector() public {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;

        string memory json = vm.readFile(VECTOR);
        bytes32 message = vm.parseJsonBytes32(json, ".messageSha256");

        // A signature over the wrong message must fail cleanly with empty returndata, never revert.
        bytes memory wrong = _sepoliaP256(rpc, sha256(abi.encodePacked(bytes32(0))), sig64);
        assertEq(wrong.length, 0, "wrong message should not verify");

        assertEq(
            bytes32(_sepoliaP256(rpc, message, sig64)),
            bytes32(uint256(1)),
            "precompile rejected the frozen vector"
        );
        // The gate accepts high-s because the chain does; prove the chain actually does.
        assertEq(
            bytes32(_sepoliaP256(rpc, message, sig64HighS)),
            bytes32(uint256(1)),
            "precompile rejected the high-s twin"
        );
    }

    function _sepoliaP256(string memory rpc, bytes32 message, bytes memory sig)
        internal
        returns (bytes memory)
    {
        string memory params = string.concat(
            '[{"to":"0x0000000000000000000000000000000000000100","input":"',
            vm.toString(abi.encodePacked(message, sig, qx, qy)),
            '"},"latest"]'
        );
        // vm.rpc hands back the result's raw bytes, so an empty result really is empty.
        return vm.rpc(rpc, "eth_call", params);
    }
}
