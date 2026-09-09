// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title FlippyGate — a 2-of-2 wallet: an AI agent proposes, a human physically approves.
/// @notice Neither key can move funds alone. `execute` requires a signature from BOTH the
///         agent key and the human key over the same EIP-712 digest. Anyone may relay the
///         call; the signatures, not msg.sender, are the authority.
/// @dev Deliberately has no spending limits, allowlists or owner rotation. Those are policy
///      features other products already ship; the point of this contract is the second hand.
contract FlippyGate is EIP712 {
    bytes32 private constant EXECUTE_TYPEHASH =
        keccak256("Execute(uint256 nonce,address to,uint256 value,bytes data,uint256 deadline)");

    address public immutable agent;

    /// @notice secp256k1 human — the Flipper. May be address(0) if only the phone is configured.
    address public immutable humanK1;

    /// @notice P-256 human — the iPhone's Secure Enclave key, as an uncompressed point.
    ///         May be (0,0) if only the Flipper is configured.
    bytes32 public immutable humanQx;
    bytes32 public immutable humanQy;

    /// @notice EIP-7951 precompile (0x100) where it exists, a deployed verifier where it does not.
    ///         Same 160-byte input either way, so this contract never branches on which it is.
    address public immutable p256Verifier;

    /// @notice Monotonic; every executed call consumes exactly one nonce. Prevents replay.
    uint256 public nonce;

    event Executed(uint256 indexed usedNonce, address indexed to, uint256 value, bytes32 digest);

    error Expired();
    error BadAgentSig();
    error BadHumanSig();
    error CallFailed(bytes ret);
    error ZeroAddress();
    error NoHumanAuthority();
    error NoK1Human();
    error NoP256Human();
    error BadHumanSigLength();

    constructor(address _agent, address _humanK1, bytes32 _humanQx, bytes32 _humanQy, address _p256Verifier)
        EIP712("FlippyGate", "1")
    {
        if (_agent == address(0)) revert ZeroAddress();
        if (_humanK1 == address(0) && _humanQx == bytes32(0)) revert NoHumanAuthority();
        if (_humanQx != bytes32(0) && _p256Verifier == address(0)) revert ZeroAddress();
        agent = _agent;
        humanK1 = _humanK1;
        humanQx = _humanQx;
        humanQy = _humanQy;
        p256Verifier = _p256Verifier;
    }

    receive() external payable {}

    /// @notice The digest both parties sign. Exposed so off-chain code can assert it matches.
    function digestOf(uint256 n, address to, uint256 value, bytes calldata data, uint256 deadline)
        public
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(
            keccak256(abi.encode(EXECUTE_TYPEHASH, n, to, value, keccak256(data), deadline))
        );
    }

    /// @notice Execute a call once both keys have signed it.
    /// @dev The nonce is consumed before the external call, and the whole transaction reverts
    ///      if the call fails — so a failed action leaves the nonce untouched and the same
    ///      signatures can be retried after the cause is fixed.
    function execute(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 deadline,
        bytes calldata agentSig,
        bytes calldata humanSig
    ) external returns (bytes memory) {
        if (block.timestamp > deadline) revert Expired();

        uint256 n = nonce;
        bytes32 digest = digestOf(n, to, value, data, deadline);

        if (ECDSA.recover(digest, agentSig) != agent) revert BadAgentSig();
        _requireHuman(digest, humanSig);

        nonce = n + 1;

        (bool ok, bytes memory ret) = to.call{value: value}(data);
        if (!ok) revert CallFailed(ret);

        emit Executed(n, to, value, digest);
        return ret;
    }

    /// @dev Two physical devices, one gate. Length is the discriminator: a secp256k1 signature is
    ///      65 bytes (r,s,v) and a P-256 one is 64 (r,s) — the Secure Enclave has no recovery id.
    function _requireHuman(bytes32 digest, bytes calldata humanSig) internal view {
        if (humanSig.length == 65) {
            if (humanK1 == address(0)) revert NoK1Human();
            if (ECDSA.recover(digest, humanSig) != humanK1) revert BadHumanSig();
            return;
        }
        if (humanSig.length != 64) revert BadHumanSigLength();
        if (humanQx == bytes32(0)) revert NoP256Human();

        // CryptoKit's SecureEnclave signer hashes its input with SHA-256 before signing and
        // offers no way to opt out, so the message is sha256(digest), not digest. Pinned by
        // packages/protocol/vectors/p256.json.
        bytes32 message = sha256(abi.encodePacked(digest));

        (bool ok, bytes memory ret) =
            p256Verifier.staticcall(abi.encodePacked(message, humanSig, humanQx, humanQy));

        // A rejection is empty returndata from the precompile but 32 zero bytes from the Solidity
        // fallback, so insist on the success word rather than testing for either failure shape.
        // High-s signatures are accepted: EIP-7951 does not reject them, and neither do we — the
        // nonce is consumed by the first execution, so a malleated twin has nothing to replay.
        if (!ok || ret.length != 32 || bytes32(ret) != bytes32(uint256(1))) revert BadHumanSig();
    }
}
