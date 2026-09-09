# Tappy — iOS app

The human half of the wallet. A chat you ask to move money, and the Secure Enclave key that
decides whether it happens.

## Run it

```bash
brew install xcodegen          # once
cd ios && xcodegen generate    # writes Tappy.xcodeproj (git-ignored)
open Tappy.xcodeproj
```

Pick your iPhone, hit run. A free Apple ID is enough — Secure Enclave and Face ID need no paid
entitlement, and you re-sign every 7 days. On the phone: Settings → Privacy & Security →
Developer Mode → on.

On first launch, tap the gear and set the hub address to **your laptop's IP on this Wi-Fi**
(`http://192.168.x.x:3000`), not `localhost` — on the phone, localhost is the phone.

## Verify the crypto without Xcode

```bash
cd ios/TappyKit && swift run tappy-verify
```

Checks Swift's keccak256 and EIP-712 digest against the same frozen vectors Solidity and
TypeScript assert. If this fails, nothing downstream is worth debugging.

## Layout

- `TappyKit/` — everything testable without a phone: keccak256, the EIP-712 digest, the Secure
  Enclave key, the hub client. Builds and runs on a Mac with only the command line tools.
- `Tappy/` — SwiftUI. Splash, onboarding, wallet, chat, approval.

## Two things worth knowing

**The Simulator has no Secure Enclave.** `SoftwareHumanKey` exists so the app runs there at all;
the UI says plainly when it is in use, because a demo that silently downgrades its own security
claim is worse than one that fails.

**The phone recomputes the digest itself** before signing, and refuses if it disagrees with the
id the server sent. That is what makes "what you see is what you sign" true here rather than
decorative.
