# Decisions

Short log of choices that are settled, so we argue about them once. If you want to reopen one,
say so in the group chat and change this file in the same PR as the code.

| # | Decision | Why | Date |
|---|---|---|---|
| 1 | The Flipper is v1's approval button, not v1's key holder | The JS engine cannot sign; a C signer is a day we do not have on day one. Cut line #1, not the foundation. | 2026-09-04 |
| 2 | Our own chat app, not an MCP connector into claude.ai | We own the UI, so the proposal, its approval state and the tx land on one screen. No tunnel, no OAuth, no connector setup on camera. | 2026-09-04 |
| 3 | Custom 2-of-2 contract, not a Safe | ~70 lines we fully understand, deployable identically on three chains in a minute, no Safe deployment needed on Arc or Hedera testnets. | 2026-09-04 |
| 4 | Both signatures verified on-chain | Makes "2-of-2" literally true. Either key alone is useless, which is the claim we will be asked about. | 2026-09-04 |
| 5 | Sepolia is the build and demo chain; Arc + Hedera are redeploys | Best faucets and tooling for the week; the sponsor deploys are the same bytecode and cost minutes. | 2026-09-04 |
| 6 | Privy server wallet for the agent key, local key behind the same interface | Prize fit and a genuinely better story (the agent never touches a raw key), with a one-env-var escape hatch. | 2026-09-04 |
| 7 | Ledger prize dropped | Cannot serve four sponsors in a week without the product becoming an accessory to integrations. The "why not a Ledger?" answer is in SPEC §9 instead. | 2026-09-04 |
| 8 | "What you see is what you sign" deferred to v2 | The device renders a summary the laptop sends. Honest about it in the README rather than implying otherwise. | 2026-09-04 |
| 9 | T3 stack for the web app | Team strength, one deploy for chat + dashboard + shop, and tRPC gives the React Native client the same typed API later. | 2026-09-04 |
| 10 | The attack scene is never cut | It is the eight seconds that make the physical step the point rather than an accessory. | 2026-09-04 |
| 11 | The iPhone is the primary approval device; the Flipper is the second | The Secure Enclave gives custody the Flipper's JS app could not, and the phone is a screen and a CPU we already trust. | 2026-09-08 |
| 12 | The human key is P-256 in the Secure Enclave, verified on-chain by EIP-7951 | Makes "the key cannot leave the device" literally true and provable on-chain. Was impossible when #1 was written. | 2026-09-08 |
| 13 | Reverses #8 — "what you see is what you sign" ships in v1 | Infeasible on the Flipper, a day's work on the iPhone. The phone recomputes the digest and will not sign a mismatch. | 2026-09-08 |
| 14 | Narrows #9 — T3 stays, as an API with no pages, renamed `apps/hub` | The client is the iOS app. A web UI is out of scope. | 2026-09-08 |
| 15 | No sessions, no spending limits, no autonomous trading | The product is a chat bot that proposes one transaction at a time and a human who approves each one. | 2026-09-08 |
| 16 | The mock shop and `propose_buy` are dropped | They needed a web surface. `send` and `swap` carry the demo, including the attack scene. | 2026-09-08 |

Superseded by these: #1 (partly), #8, #9. Still binding: #2, #3, #4, #5, #6, #10.

| 17 | The NFC tap is read by the **Flipper**, not the iPhone | Core NFC needs a paid Apple Developer account we do not have. The Flipper has NFC hardware and needs no entitlement. Costs a Flipper C app, since mJS has no NFC module. | 2026-09-09 |
| 18 | Two approval devices, one gate | Flipper approves with secp256k1 (65-byte sig), iPhone with a Secure Enclave P-256 key (64-byte sig). `FlippyGate` dispatches on signature length, so neither device knows the other exists. | 2026-09-09 |
| 19 | The hub keeps state in memory, not Postgres | It is a four-minute demo. A database is one more thing that can break on stage, and nothing here is worth surviving a restart. Reverses the Supabase half of #9. | 2026-09-09 |

