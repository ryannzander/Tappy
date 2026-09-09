import { ALLOWED_TRANSITIONS, type Device, type Proposal, type ProposalStatus } from "@flippy/protocol";

/**
 * Everything the demo remembers, in memory. A restart forgets it all, which is correct
 * for a hackathon: there is nothing here worth surviving a crash, and a database is one
 * more thing that can be broken on stage.
 *
 * Next's dev server keeps one module instance per process, so a Map is enough. Under
 * `next build` with multiple workers this would need somewhere real to live.
 */
const proposals = new Map<string, Proposal>();
const devices = new Map<string, Device>();
const messages: ChatMessage[] = [];

export interface ChatMessage {
  role: "user" | "assistant";
  text: string;
  /** Proposal ids created during this turn, so the app can render cards inline. */
  proposalIds?: string[];
  at: number;
}

export function putProposal(p: Proposal): void {
  proposals.set(p.id.toLowerCase(), p);
}

export function getProposal(id: string): Proposal | undefined {
  return proposals.get(id.toLowerCase());
}

export function listProposals(limit = 20): Proposal[] {
  return [...proposals.values()].sort((a, b) => b.createdAt - a.createdAt).slice(0, limit);
}

/**
 * The only way a proposal's status changes. An illegal move is a bug in our own code,
 * so it throws — a proposal that silently slid from REJECTED to EXECUTED is the exact
 * failure this whole project exists to make impossible.
 */
export function transition(id: string, next: ProposalStatus, patch: Partial<Proposal> = {}): Proposal {
  const p = getProposal(id);
  if (!p) throw new Error(`unknown proposal ${id}`);
  if (!ALLOWED_TRANSITIONS[p.status].includes(next)) {
    throw new Error(`illegal transition ${p.status} -> ${next} for ${id}`);
  }
  const updated: Proposal = { ...p, ...patch, status: next };
  proposals.set(p.id.toLowerCase(), updated);
  return updated;
}

export function putDevice(d: Device): void {
  devices.set(d.id, d);
}

export function listDevices(): Device[] {
  return [...devices.values()];
}

export function getDevice(id: string): Device | undefined {
  return devices.get(id);
}

/**
 * Mirrored from the phone. Only ever used to turn a name into an address for the agent — the
 * phone still re-derives the digest of whatever comes back, so a bad entry here cannot make
 * anyone sign something they did not read.
 */
export interface Contact {
  id: string;
  name: string;
  handle: string;
  address: string;
}

let contacts: Contact[] = [];

export function setContacts(next: Contact[]): void {
  contacts = next;
}

export function listContacts(): Contact[] {
  return contacts;
}

export function addMessage(m: ChatMessage): void {
  messages.push(m);
}

export function listMessages(): ChatMessage[] {
  return messages;
}
