import type { Address } from "viem";

/**
 * What the wallet can hold. The gate executes arbitrary calldata, so an ERC-20 transfer needs
 * no contract change at all — a token send is the same `execute` with `to` pointing at the
 * token and the amount encoded in `data`.
 */
export interface TokenInfo {
  symbol: string;
  name: string;
  decimals: number;
  /** Absent for the chain's native coin. */
  address?: Address;
  /** Coinbase spot pair, where a real market price exists. */
  pair?: string;
  /** Demo tokens have no market, so they get a fixed price rather than a missing one. */
  fixedUsd?: number;
}

export const NATIVE: TokenInfo = {
  symbol: "ETH",
  name: "Ether",
  decimals: 18,
  pair: "ETH-USD",
};

/**
 * Well-known Sepolia deployments. Balances are read for all of these; the ones sitting at zero
 * are simply not shown, so the list reflects what is actually held rather than what exists.
 */
export const SEPOLIA_TOKENS: TokenInfo[] = [
  NATIVE,
  {
    symbol: "USDC",
    name: "USD Coin",
    decimals: 6,
    address: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
    fixedUsd: 1,
  },
  {
    symbol: "LINK",
    name: "Chainlink",
    decimals: 18,
    address: "0x779877A7B0D9E8603169DdbD7836e478b4624789",
    pair: "LINK-USD",
  },
  {
    symbol: "WETH",
    name: "Wrapped Ether",
    decimals: 18,
    address: "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14",
    pair: "ETH-USD",
  },
];

/** FLIP's address is only known once the mocks are deployed, so it is appended at runtime. */
export function flipToken(address: Address): TokenInfo {
  return { symbol: "FLIP", name: "Flippy Test Token", decimals: 18, address, fixedUsd: 0.25 };
}

export function findToken(tokens: TokenInfo[], symbolOrAddress: string): TokenInfo | undefined {
  const needle = symbolOrAddress.trim().toLowerCase();
  return tokens.find(
    (t) => t.symbol.toLowerCase() === needle || t.address?.toLowerCase() === needle,
  );
}

export const isNative = (t: TokenInfo): boolean => t.address === undefined;

/**
 * Decimal string -> base units, by string surgery rather than arithmetic. USDC has 6 decimals
 * and ETH has 18; going through a Double loses precision on both, silently and in the direction
 * that moves the wrong amount of money.
 */
export function toBaseUnits(amount: string, decimals: number): bigint {
  const cleaned = amount.trim().replace(/,/g, "");
  if (!/^\d*\.?\d*$/.test(cleaned) || cleaned === "" || cleaned === ".") {
    throw new Error(`"${amount}" is not a number`);
  }
  const [whole = "0", fraction = ""] = cleaned.split(".");
  if (fraction.length > decimals) {
    throw new Error(`${amount} has more than ${decimals} decimal places`);
  }
  return BigInt(whole + fraction.padEnd(decimals, "0"));
}

/** Base units -> a decimal string, trimmed. The inverse of `toBaseUnits`. */
export function fromBaseUnits(value: bigint, decimals: number, places = 6): string {
  const negative = value < 0n;
  const digits = (negative ? -value : value).toString().padStart(decimals + 1, "0");
  const whole = digits.slice(0, digits.length - decimals);
  const fraction = digits.slice(digits.length - decimals).slice(0, places).replace(/0+$/, "");
  return `${negative ? "-" : ""}${whole}${fraction ? "." + fraction : ""}`;
}
