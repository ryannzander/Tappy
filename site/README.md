# site

The public page at <https://ryannzander.github.io/Tappy/>. Plain HTML, CSS and ES modules — no
build step, no dependencies, so `.github/workflows/pages.yml` uploads this directory as-is on
every push to `main` that touches it.

```bash
cd site && python3 -m http.server 4180    # http://localhost:4180
```

`digest.js` is a from-scratch keccak256 and EIP-712 encoder so the hero can recompute the
proposal hash in the visitor's browser. It is **not** a second implementation of the protocol to
keep in sync — it exists to be checked against `packages/protocol/vectors/execute.json`, which
the "Load the frozen vector" button does live. If that button ever shows a mismatch, this file is
wrong and the page is lying; fix it here, never in the vector.

Screenshots in `img/` are copies of `docs/press/`. Re-copy them when the press kit changes.

Turn Pages on once, under Settings → Pages → Source → GitHub Actions.
