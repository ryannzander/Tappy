// keccak256 and the TappyGate EIP-712 digest, with no dependencies and no build step, so the
// page can recompute the hash in the visitor's browser the same way the iPhone recomputes it.
// Checked against packages/protocol/vectors/execute.json — see the "frozen vector" control.

const MASK = (1n << 64n) - 1n;

const RC = [
  0x0000000000000001n, 0x0000000000008082n, 0x800000000000808an, 0x8000000080008000n,
  0x000000000000808bn, 0x0000000080000001n, 0x8000000080008081n, 0x8000000000008009n,
  0x000000000000008an, 0x0000000000000088n, 0x0000000080008009n, 0x000000008000000an,
  0x000000008000808bn, 0x800000000000008bn, 0x8000000000008089n, 0x8000000000008003n,
  0x8000000000008002n, 0x8000000000000080n, 0x000000000000800an, 0x800000008000000an,
  0x8000000080008081n, 0x8000000000008080n, 0x0000000080000001n, 0x8000000080008008n,
];

// rho offsets, indexed [x][y]
const R = [
  [0n, 36n, 3n, 41n, 18n],
  [1n, 44n, 10n, 45n, 2n],
  [62n, 6n, 43n, 15n, 61n],
  [28n, 55n, 25n, 21n, 56n],
  [27n, 20n, 39n, 8n, 14n],
];

const rotl = (x, n) => (n === 0n ? x : ((x << n) | (x >> (64n - n))) & MASK);

function keccakF(A) {
  const C = new Array(5);
  const D = new Array(5);
  const B = new Array(25);
  for (let round = 0; round < 24; round++) {
    for (let x = 0; x < 5; x++) {
      C[x] = A[x] ^ A[x + 5] ^ A[x + 10] ^ A[x + 15] ^ A[x + 20];
    }
    for (let x = 0; x < 5; x++) {
      D[x] = C[(x + 4) % 5] ^ rotl(C[(x + 1) % 5], 1n);
    }
    for (let x = 0; x < 5; x++) {
      for (let y = 0; y < 5; y++) A[x + 5 * y] ^= D[x];
    }
    for (let x = 0; x < 5; x++) {
      for (let y = 0; y < 5; y++) {
        B[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(A[x + 5 * y], R[x][y]);
      }
    }
    for (let x = 0; x < 5; x++) {
      for (let y = 0; y < 5; y++) {
        A[x + 5 * y] = B[x + 5 * y] ^ (~B[((x + 1) % 5) + 5 * y] & B[((x + 2) % 5) + 5 * y] & MASK);
      }
    }
    A[0] ^= RC[round];
  }
  return A;
}

/** keccak256 over a byte array, returned as 32 bytes. */
export function keccak256(bytes) {
  const rate = 136;
  const padded = new Uint8Array(Math.ceil((bytes.length + 1) / rate) * rate);
  padded.set(bytes);
  padded[bytes.length] |= 0x01; // Keccak padding, not SHA-3's 0x06
  padded[padded.length - 1] |= 0x80;

  const A = new Array(25).fill(0n);
  for (let off = 0; off < padded.length; off += rate) {
    for (let i = 0; i < rate / 8; i++) {
      let lane = 0n;
      for (let b = 7; b >= 0; b--) lane = (lane << 8n) | BigInt(padded[off + i * 8 + b]);
      A[i] ^= lane;
    }
    keccakF(A);
  }

  const out = new Uint8Array(32);
  for (let i = 0; i < 4; i++) {
    let lane = A[i];
    for (let b = 0; b < 8; b++) {
      out[i * 8 + b] = Number(lane & 0xffn);
      lane >>= 8n;
    }
  }
  return out;
}

export const toHex = (bytes) =>
  "0x" + Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");

export function fromHex(hex) {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  return out;
}

const utf8 = (s) => new TextEncoder().encode(s);
const concat = (chunks) => {
  const out = new Uint8Array(chunks.reduce((n, c) => n + c.length, 0));
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.length;
  }
  return out;
};

/** One abi.encode word: uints right-aligned, addresses right-aligned in 32 bytes. */
function word(value) {
  const out = new Uint8Array(32);
  let v = BigInt(value);
  for (let i = 31; i >= 0 && v > 0n; i--) {
    out[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  return out;
}

const hashString = (s) => keccak256(utf8(s));

const DOMAIN_TYPE = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
const EXECUTE_TYPE = "Execute(uint256 nonce,address to,uint256 value,bytes data,uint256 deadline)";

export function domainSeparator(chainId, gate) {
  return keccak256(
    concat([
      hashString(DOMAIN_TYPE),
      hashString("TappyGate"),
      hashString("1"),
      word(chainId),
      word(gate),
    ]),
  );
}

export function structHash({ nonce, to, value, data, deadline }) {
  return keccak256(
    concat([
      hashString(EXECUTE_TYPE),
      word(nonce),
      word(to),
      word(value),
      keccak256(fromHex(data)), // viem and Solidity both hash `bytes` args
      word(deadline),
    ]),
  );
}

/** The one hash the agent, the phone and TappyGate all sign over. */
export function proposalDigest(p) {
  return keccak256(
    concat([new Uint8Array([0x19, 0x01]), domainSeparator(p.chainId, p.gate), structHash(p)]),
  );
}
