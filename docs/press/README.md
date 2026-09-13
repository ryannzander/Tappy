# Press kit

Screenshots are real: captured from the running app against the live Sepolia deployment, not
mocked. The balances, the proposal id and the agent's replies are all genuine.

## Screenshots

| File | What it shows | Suggested caption |
|---|---|---|
| `04-approval.png` | **The one to lead with.** | "The AI can propose. It cannot send. The phone rebuilds the transaction hash itself and refuses to sign if the server lied." |
| `02-chat.png` | Chat with a real proposal | "Ask in plain English. It reads the chain, converts to dollars, and warns you before it spends." |
| `01-home.png` | Balance and holdings | "One wallet, several coins, on Sepolia." |
| `03-recipients.png` | Saved recipients | "Pay a name, not 42 characters of hex." |

## Logo

| File | Use |
|---|---|
| `cover.png` | 16:9 submission header |
| `logo-wordmark-light.png` | Wordmark on white |
| `logo-wordmark-lime.png` | Wordmark on brand lime |
| `logo-wordmark-dark.png` | Wordmark reversed out of the ink |
| `logo-square-lime.png` | Square avatar, 1024px |
| `logo-square-light.png` | Square avatar on white |

The mark is three rings closing on a point of contact — the product in one glyph: something was
touched, and only then did it happen.

Brand: lime `#9FE870`, ink `#163300`, white. The ink is a forest green that reads as black but
never is.

## One line

> Your AI can ask. Only you can approve.

## Paragraph

> Tappy is a wallet you talk to. Ask it to send money and it prepares the transaction — but it
> cannot send anything. The wallet needs two signatures, and the second is held in your iPhone's
> Secure Enclave, released only by your face. The contract verifies both on-chain using
> Ethereum's P-256 precompile, so a compromised agent is still just an agent asking.

## Claims that are true, and worth checking

- The Secure Enclave key cannot be exported, copied or backed up. Verified on hardware.
- The phone recomputes the EIP-712 digest from the raw call and refuses to sign a mismatch, so a
  hostile server cannot change what you approve.
- keccak256 and the digest are reproduced in Solidity, TypeScript and Swift against the same
  frozen test vectors.
- A prompt injection hidden in a token listing really does compromise the agent — and declining
  on the device leaves the balance byte-identical.
