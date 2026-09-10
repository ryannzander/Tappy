// Tappy — approval app for Flipper Zero (JS engine).
//
// This app is the physical gate. The laptop bridge writes a request to inbox.json; this shows
// it and writes the human's decision to outbox.json. No key material lives here in v1.
//
// Install:  pnpm --filter @tappy/bridge flipper:install
// Run:      Apps -> Scripts -> tappy.js
//
// The storage API differs between firmware versions and forks: some builds expose
// storage.exists/read/write, others only fileExists/openFile. mJS has no exceptions, so a
// wrong guess here does not throw something readable — the app just stops. Everything below
// therefore feature-detects instead of assuming, and prints what it found, so a failure names
// itself instead of looking like a dead device.

let storage = require("storage");
let dialog = require("dialog");
let notify = require("notification");

let DIR = "/ext/apps_data/tappy";
let INBOX = DIR + "/inbox.json";
let OUTBOX = DIR + "/outbox.json";
let POLL_MS = 300;

let lastSeq = 0;

function has(fn) {
  return typeof storage[fn] === "function";
}

function exists(path) {
  if (has("fileExists")) return storage.fileExists(path);
  if (has("fileOrDirExists")) return storage.fileOrDirExists(path);
  if (has("exists")) return storage.exists(path);
  return false;
}

function readText(path) {
  if (has("read")) return storage.read(path);
  if (has("readFile")) return storage.readFile(path);
  if (has("openFile")) {
    let f = storage.openFile(path, "r", "open_existing");
    if (!f) return undefined;
    let text = f.read("ascii", 4096);
    f.close();
    return text;
  }
  return undefined;
}

function writeText(path, text) {
  if (has("write")) return storage.write(path, text);
  if (has("writeFile")) return storage.writeFile(path, text);
  if (has("openFile")) {
    let f = storage.openFile(path, "w", "create_always");
    if (!f) return false;
    f.write(text);
    f.close();
    return true;
  }
  return false;
}

function removeFile(path) {
  if (has("remove")) return storage.remove(path);
  if (has("delete")) return storage["delete"](path);
  return false;
}

function ensureDir(path) {
  if (has("makeDirectory")) return storage.makeDirectory(path);
  if (has("mkdir")) return storage.mkdir(path);
  return false;
}

// One line naming the API this firmware actually has. If the app misbehaves, this is the first
// thing to read, and it is worth the two seconds it costs at startup.
print("Tappy: storage api ->",
  "exists:" + (has("fileExists") ? "fileExists" : has("exists") ? "exists" : "NONE"),
  "read:" + (has("read") ? "read" : has("openFile") ? "openFile" : "NONE"),
  "write:" + (has("write") ? "write" : has("openFile") ? "openFile" : "NONE"));

ensureDir(DIR);

function screenFor(req) {
  // 128x64 pixels: three short lines is the whole budget.
  return req.action + " " + req.amount + "\n" + "to " + req.counterparty + "\n" + req.chain;
}

function announce() {
  if (typeof notify.blink === "function") notify.blink("blue", "short");
  if (typeof notify.success === "function") notify.success();
}

function respond(req, approved) {
  writeText(
    OUTBOX,
    JSON.stringify({ id: req.id, seq: req.seq, approved: approved, at: Date.now() })
  );
  if (approved) {
    if (typeof notify.success === "function") notify.success();
  } else if (typeof notify.error === "function") {
    notify.error();
  }
}

print("Tappy: waiting for approval requests...");

while (true) {
  let req = undefined;

  if (exists(INBOX)) {
    let raw = readText(INBOX);
    // A half-written file parses to nothing rather than wedging the loop. The bridge writes
    // the whole file in one CLI command, but polling can still land mid-write.
    if (raw) req = JSON.parse(raw);
  }

  if (req && req.seq !== undefined && req.seq > lastSeq) {
    lastSeq = req.seq;
    announce();

    let choice = dialog.custom({
      header: "TAPPY " + req.short,
      text: screenFor(req),
      button_left: "Reject",
      button_right: "Approve",
    });

    // Back returns an empty string, and a Back press is not an approval.
    let approved = choice === "Approve";
    respond(req, approved);
    removeFile(INBOX);
    print("Tappy: " + (approved ? "approved" : "rejected") + " #" + req.seq);
  }

  delay(POLL_MS);
}
