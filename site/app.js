import { proposalDigest, toHex } from "./digest.js";

const VECTOR = {
  gate: "0x1111111111111111111111111111111111111111",
  nonce: "0",
  to: "0x2222222222222222222222222222222222222222",
  amount: "0.01",
  digest: "0x73e15f59e63a1ef10b8f830801790311715be1acf9fb4fb2884cbd1ab532021a",
};

const ATTACKER = "0xbAD0000000000000000000000000000000000bAD";
const CHAIN_ID = 11155111;
const DEADLINE = "2000000000";

const el = (id) => document.getElementById(id);
const fields = { amount: el("amount"), to: el("to"), nonce: el("nonce"), gate: el("gate") };
const phoneHash = el("phone-hash");
const serverHash = el("server-hash");
const serverBlock = el("server-hash-block");
const shaBlock = el("sha-block");
const shaHash = el("sha-hash");
const verdict = el("verdict");
const stateTitle = el("state-title");
const stateBody = el("state-body");
const vectorCheck = el("vector-check");
const lieButton = el("lie");

let lying = false;

/** Decimal ETH to wei without floating point, because 0.0047 * 1e18 is not an integer. */
function toWei(input) {
  const clean = String(input).trim().replace(/,/g, "");
  if (!/^\d*\.?\d*$/.test(clean) || clean === "" || clean === ".") return null;
  const [whole = "0", frac = ""] = clean.split(".");
  if (frac.length > 18) return null;
  return BigInt(whole || "0") * 10n ** 18n + BigInt((frac + "0".repeat(18)).slice(0, 18));
}

function readAddress(input) {
  const clean = String(input).trim();
  return /^0x[0-9a-fA-F]{40}$/.test(clean) ? clean : null;
}

function readCall() {
  const value = toWei(fields.amount.value);
  const to = readAddress(fields.to.value);
  const gate = readAddress(fields.gate.value);
  const nonceText = fields.nonce.value.trim();
  const nonce = /^\d+$/.test(nonceText) ? nonceText : null;

  const bad = [];
  if (value === null) bad.push("the amount");
  if (to === null) bad.push("the recipient");
  if (gate === null) bad.push("the gate address");
  if (nonce === null) bad.push("the nonce");
  if (bad.length) return { bad };

  return { call: { chainId: CHAIN_ID, gate, nonce, to, value, data: "0x", deadline: DEADLINE } };
}

const HEX = "0123456789abcdef";

/** One short scramble when a hash changes, so it is obvious that every field moves every bit. */
function showHash(node, hex) {
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduced || node.dataset.value === hex) {
    node.textContent = hex;
    node.dataset.value = hex;
    return;
  }
  node.dataset.value = hex;
  clearInterval(Number(node.dataset.timer));
  let frame = 0;
  const timer = setInterval(() => {
    frame++;
    if (frame > 5 || node.dataset.value !== hex) {
      clearInterval(timer);
      if (node.dataset.value === hex) node.textContent = hex;
      return;
    }
    const settled = 2 + frame * 12;
    node.textContent =
      hex.slice(0, settled) +
      Array.from({ length: hex.length - settled }, () => HEX[(Math.random() * 16) | 0]).join("");
  }, 45);
  node.dataset.timer = String(timer);
}

// CryptoKit hashes whatever it is given, so the Enclave signs sha256(digest) and TappyGate
// verifies that. Shown here because it is the step people get wrong when reimplementing this.
let shaToken = 0;
async function showEnclaveHash(digestBytes) {
  const token = ++shaToken;
  if (!window.crypto?.subtle) return;
  const sum = new Uint8Array(await crypto.subtle.digest("SHA-256", digestBytes));
  if (token !== shaToken) return;
  shaHash.textContent = toHex(sum);
  shaBlock.hidden = false;
}

function render() {
  const { call, bad } = readCall();

  if (bad) {
    shaToken++;
    verdict.dataset.state = "invalid";
    serverBlock.hidden = true;
    shaBlock.hidden = true;
    phoneHash.textContent = "—";
    phoneHash.dataset.value = "";
    stateTitle.textContent = "Nothing to sign";
    stateBody.textContent = `Check ${bad.join(" and ")}. An address is 0x and 40 hex characters.`;
    vectorCheck.hidden = true;
    return;
  }

  const digestBytes = proposalDigest(call);
  const shown = toHex(digestBytes);
  showHash(phoneHash, shown);

  if (lying) {
    shaToken++;
    shaBlock.hidden = true;
    const asked = toHex(proposalDigest({ ...call, to: ATTACKER }));
    serverBlock.hidden = false;
    showHash(serverHash, asked);
    verdict.dataset.state = "refused";
    stateTitle.textContent = "This iPhone will not sign";
    stateBody.textContent =
      "The server asked for a hash that does not describe the transaction on the screen — it sends to " +
      ATTACKER.slice(0, 6) +
      "…" +
      ATTACKER.slice(-4) +
      " instead. Face ID is never shown, so the key is never used.";
    vectorCheck.hidden = true;
    return;
  }

  serverBlock.hidden = true;
  showEnclaveHash(digestBytes);
  verdict.dataset.state = "ok";
  stateTitle.textContent = "Face ID releases the key";
  stateBody.textContent =
    "The hash matches the transaction on the screen. The Secure Enclave signs sha256 of it, and TappyGate verifies that signature on-chain next to the agent's.";

  const isVector =
    call.gate.toLowerCase() === VECTOR.gate &&
    call.to.toLowerCase() === VECTOR.to &&
    call.nonce === VECTOR.nonce &&
    call.value === 10000000000000000n;
  vectorCheck.hidden = !isVector;
  if (isVector) {
    const same = shown === VECTOR.digest;
    vectorCheck.dataset.ok = String(same);
    vectorCheck.textContent = same
      ? "Byte-identical to vectors/execute.json — the same hash Solidity, TypeScript and Swift produce."
      : "This does not match vectors/execute.json. Something in this page is wrong.";
  }
}

for (const input of Object.values(fields)) {
  input.addEventListener("input", render);
}

lieButton.addEventListener("click", () => {
  lying = !lying;
  lieButton.textContent = lying ? "Stop lying" : "Let the server lie";
  lieButton.dataset.active = String(lying);
  lieButton.setAttribute("aria-pressed", String(lying));
  render();
});

el("vector").addEventListener("click", () => {
  fields.amount.value = VECTOR.amount;
  fields.to.value = VECTOR.to;
  fields.nonce.value = VECTOR.nonce;
  fields.gate.value = VECTOR.gate;
  render();
});

render();
