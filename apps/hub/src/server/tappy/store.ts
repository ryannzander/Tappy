import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import {
  ALLOWED_TRANSITIONS,
  proposalSchema,
  type Device,
  type Proposal,
  type ProposalStatus,
} from "@tappy/protocol";

/**
 * Everything the demo remembers, in a JSON file.
 *
 * It started as a module-level Map, which was wrong for a reason that is invisible until it
 * bites: Next's dev server gives each route handler its own module instance, so a proposal
 * created by /api/m/chat was genuinely not there when /api/m/proposals/:id looked for it.
 * The symptom is a proposal that vanishes between two requests a second apart.
 *
 * A file is shared by construction, survives a restart mid-demo, and is quick enough that
 * reading it on every request costs nothing at this size.
 */

export interface ChatMessage {
  role: "user" | "assistant";
  text: string;
  /** Proposal ids created during this turn, so the app can render cards inline. */
  proposalIds?: string[];
  at: number;
}

export interface Contact {
  id: string;
  name: string;
  handle: string;
  address: string;
}

interface State {
  proposals: Proposal[];
  devices: Device[];
  contacts: Contact[];
  messages: ChatMessage[];
}

const FILE = resolve(process.cwd(), process.cwd().endsWith("apps/hub") ? "../../.tappy-state.json" : ".tappy-state.json");

const EMPTY: State = { proposals: [], devices: [], contacts: [], messages: [] };

function load(): State {
  try {
    const raw = JSON.parse(readFileSync(FILE, "utf8")) as State;
    return {
      // Revive through the schema so wei and nonce come back as bigints, not strings.
      proposals: (raw.proposals ?? []).map((p) => proposalSchema.parse(p)),
      devices: raw.devices ?? [],
      contacts: raw.contacts ?? [],
      messages: raw.messages ?? [],
    };
  } catch {
    return { ...EMPTY };
  }
}

function save(state: State): void {
  mkdirSync(dirname(FILE), { recursive: true });
  writeFileSync(
    FILE,
    JSON.stringify(state, (_k, v) => (typeof v === "bigint" ? v.toString() : v), 2),
  );
}

/** Enough history for a demo and a video; beyond that the file is just growing. */
const MAX_PROPOSALS = 100;
const MAX_MESSAGES = 200;

export function putProposal(p: Proposal): void {
  const state = load();
  state.proposals = [
    p,
    ...state.proposals.filter((x) => x.id.toLowerCase() !== p.id.toLowerCase()),
  ].slice(0, MAX_PROPOSALS);
  save(state);
}

export function getProposal(id: string): Proposal | undefined {
  return load().proposals.find((p) => p.id.toLowerCase() === id.toLowerCase());
}

export function listProposals(limit = 20): Proposal[] {
  return load()
    .proposals.sort((a, b) => b.createdAt - a.createdAt)
    .slice(0, limit);
}

/**
 * The only way a proposal's status changes. An illegal move is a bug in our own code, so it
 * throws — a proposal that silently slid from REJECTED to EXECUTED is the exact failure this
 * whole project exists to make impossible.
 */
export function transition(id: string, next: ProposalStatus, patch: Partial<Proposal> = {}): Proposal {
  const state = load();
  const current = state.proposals.find((p) => p.id.toLowerCase() === id.toLowerCase());
  if (!current) throw new Error(`unknown proposal ${id}`);
  if (!ALLOWED_TRANSITIONS[current.status].includes(next)) {
    throw new Error(`illegal transition ${current.status} -> ${next} for ${id}`);
  }
  const updated: Proposal = { ...current, ...patch, status: next };
  state.proposals = state.proposals.map((p) => (p.id === current.id ? updated : p));
  save(state);
  return updated;
}

export function putDevice(d: Device): void {
  const state = load();
  state.devices = [d, ...state.devices.filter((x) => x.publicKey !== d.publicKey)];
  save(state);
}

export function listDevices(): Device[] {
  return load().devices;
}

export function getDevice(id: string): Device | undefined {
  return load().devices.find((d) => d.id === id);
}

/**
 * Mirrored from the phone. Only ever used to turn a name into an address for the agent — the
 * phone still re-derives the digest of whatever comes back, so a bad entry here cannot make
 * anyone sign something they did not read.
 */
export function setContacts(next: Contact[]): void {
  const state = load();
  state.contacts = next;
  save(state);
}

export function listContacts(): Contact[] {
  return load().contacts;
}

export function addMessage(m: ChatMessage): void {
  const state = load();
  state.messages = [...state.messages, m].slice(-MAX_MESSAGES);
  save(state);
}

/** Clearing the chat on the phone should clear it here too, or the agent keeps a memory the
 *  user believes they deleted — which is both surprising and, with an injection in scope, unsafe. */
export function clearMessages(): void {
  const state = load();
  state.messages = [];
  save(state);
}

export function listMessages(): ChatMessage[] {
  return load().messages;
}
