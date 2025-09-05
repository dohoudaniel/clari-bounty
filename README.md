> **ClariBounty** — a modular, production-oriented Clarity project implementing a micro-bounty marketplace.
> Owners post bounties and fund an on-chain escrow; contributors stake, submit work, and earn reputation points + badge NFTs when paid. Includes escrow, staking, reputation, badge-NFT, arbitrator, governance, and utility contracts — plus a full Clarinet test-suite and developer guides.

---

# Table of contents

1. [Project summary](#project-summary)
2. [Why ClariBounty?](#why-claribounty)
3. [High-level architecture](#high-level-architecture)
4. [Repository layout](#repository-layout)
5. [Prerequisites](#prerequisites)
6. [Install & run (quickstart)](#install--run-quickstart)
7. [Running the tests & checks](#running-the-tests--checks)
8. [API reference (public functions)](#api-reference-public-functions)
9. [Example flows (copy-paste friendly)](#example-flows-copy-paste-friendly)
10. [Testing plan & mapping to contracts](#testing-plan--mapping-to-contracts)
11. [Debugging & troubleshooting guide](#debugging--troubleshooting-guide)
12. [Security considerations & limitations](#security-considerations--limitations)
13. [How to produce a meaningful Pull Request (PR checklist)](#how-to-produce-a-meaningful-pull-request-pr-checklist)
14. [Contribution guide & style notes](#contribution-guide--style-notes)
15. [License & credits](#license--credits)

---

# Project summary

ClariBounty is a Clarity-based micro-bounty marketplace designed for small tasks (documentation, tiny code fixes, design micro-tasks, etc.). The repo is modularized across several Clarity contracts so responsibilities are separated (escrow, staking, reputation, badges, arbitrator, governance, utilities). The codebase is engineered to:

* pass `clarinet check` (syntax + static checks),
* include **≥ 7** contract files,
* include **≥ 300** lines of Clarity code across contracts,
* ship a full test-suite with happy-path, dispute, refund, and governance tests,
* ship a meaningful README and PR template for reviewers.

---

# Why ClariBounty?

* Encourages accountable micro-work that’s transparent on-chain.
* Demonstrates modular Clarity engineering patterns (small contracts, `ok/err` patterns, use of maps & tuples, inter-contract calls).
* Great project for technical interviews / portfolio: smart contract logic + test coverage + documentation + PR process.

---

# High-level architecture

* **utils.clar** — constants, error codes, shared helpers.
* **bounty-registry.clar** — core flows: create bounty, submit work, accept/reject, mark winner, query bounties.
* **escrow\.clar** — hold & release STX per-bounty; called by `bounty-registry` or `arbitrator`.
* **staking.clar** — contributor stake logic (per-bounty stakes, withdrawal rules).
* **reputation.clar** — non-transferable reputation ledger (principal → points).
* **badge-nft.clar** — badge minting (simple minimal NFT pattern).
* **arbitrator.clar** — dispute resolution and award/refund logic.
* **governance.clar** — admin settings (fee rate, dispute window, admin).

Design patterns used:

* `ok`/`err` results for public functions.
* `map`, `map-get`, `map-set` for persistent storage.
* Minimal on-chain loops — single-step operations where possible.
* Inter-contract calls (e.g., `contract-call? .escrow release-funds ...`).

---

# Repository layout

```
ClariBounty/
├─ contracts/
│  ├─ utils.clar
│  ├─ bounty-registry.clar
│  ├─ escrow.clar
│  ├─ staking.clar
│  ├─ reputation.clar
│  ├─ badge-nft.clar
│  ├─ arbitrator.clar
│  └─ governance.clar
├─ tests/
│  ├─ bounty-tests.ts
│  ├─ escrow-tests.ts
│  ├─ dispute-tests.ts
│  └─ governance-tests.ts
├─ Clarinet.toml
├─ README.md                <-- this file
├─ PR_TEMPLATE.md
└─ .github/
   └─ workflows/
      └─ clarinet-ci.yml    (optional: CI to run `clarinet check` & `clarinet test`)
```

---

# Prerequisites

* Node.js (recommended LTS, e.g. 18.x or 20.x) for Clarinet JS tests.
* Clarinet CLI installed. Quick install options:

  * Homebrew (macOS): `brew install clarinet`
  * Cargo or prebuilt binary — see Clarinet docs: [https://docs.hiro.so/stacks/clarinet/quickstart](https://docs.hiro.so/stacks/clarinet/quickstart)
* Git, and a GitHub account for PRs.
* (Optional) VSCode with Clarity and Clarinet extensions for linting & inline debugging.

---

# Install & run (quickstart)

1. Clone the repo

```bash
git clone https://github.com/<your-username>/clari-bounty.git
cd clari-bounty
```

2. Install JS test deps (if included):

```bash
npm install
# or
yarn install
```

3. Run static check (syntax + lints):

```bash
clarinet check
```

This runs Clarinet's contract checks over the `contracts/` folder defined in `Clarinet.toml`.

4. Run the test suite:

```bash
clarinet test
```

This starts a seeded local devnet and runs the Clarinet JS tests (Vitest/Jest style).

5. Developer REPL (manual interaction):

```bash
clarinet console
```

Once in the console you can run contract calls such as:

```
(contract-call? .bounty-registry create-bounty "Title" "ipfs://Qm..." u1000000 u500)
```

> NOTE: exact function signatures are listed in the API reference below — use the exact names and argument types from the deployed contracts shown in the console.

---

# Running the tests & checks (details)

* `clarinet check` — validate Clarity syntax and contract dependencies.
* `clarinet test` — run the TypeScript/JS test harness. The tests included cover:

  * Happy path (create → stake → submit → accept → payout),
  * Refund path (deadline expired → owner reclaim),
  * Dispute path (owner rejects → arbitrator awards),
  * Governance restrictions (admin-only actions),
  * Stake safety (prevent unauthorized stake withdrawal).

If using CI (GitHub Actions), include a workflow step:

```yaml
- name: Run Clarinet checks
  run: clarinet check

- name: Run Clarinet tests
  run: clarinet test
```

---

# API reference (public functions)

Below are the **expected** public function signatures and semantics for each contract. Use these as the primary source when writing tests & scripts. (When implementing, keep these names & semantics — they are chosen for clarity and testability.)

> **Important**: The exact ABI is present in the `contracts/*.clar` files in this repo. The examples below are canonical; if you change names, update tests.

---

## `utils.clar` (helpers & constants)

**Public constants**

* `ERR-BOUNTY-NOT-FOUND` — `(err u100)`
* `ERR-NOT-OWNER` — `(err u101)`
* `ERR-INSUFFICIENT-FUNDS` — `(err u102)`
* `ERR-NOT-ADMIN` — `(err u150)`

(Utilities are primarily `internal-read` / `public-read` helpers. No heavy public functions.)

---

## `bounty-registry.clar` — core of marketplace

**Public functions**

* `(define-public (create-bounty (title (string-ascii 128)) (ipfs-hash (string-ascii 128)) (reward uint) (deadline uint)) (response uint uint))`
  *Creates a bounty. Transfers reward amount to escrow. Returns `(ok bounty-id)` or `(err ERR-...)`.*

* `(define-public (submit-work (bounty-id uint) (submission-hash (string-ascii 128))) (response bool uint))`
  *Allows staked contributor to submit. Stores submission and marks submitted-by principal. Returns `ok true`.*

* `(define-public (owner-accept (bounty-id uint) (submission-index uint)) (response bool uint))`
  *Owner accepts a submission. Triggers `escrow` release to contributor, awards reputation and mints badge.*

* `(define-public (owner-reject (bounty-id uint) (submission-index uint) (reason (string-ascii 256))) (response bool uint))`
  *Owner rejects — contributor may open dispute subsequently.*

* `(define-public (reclaim-funds (bounty-id uint)) (response bool uint))`
  *If deadline passed and no successful submission, owner reclaims funds to owner.*

* `(define-read-only (get-bounty (bounty-id uint)) (option (tuple (owner principal) (reward uint) (deadline uint) (status uint) (ipfs-hash (string-ascii 128)))) )`
  *Query bounty record.*

---

## `escrow.clar`

**Public functions**

* `(define-public (deposit (bounty-id uint)) (response bool uint))`
  *Used by `bounty-registry` on create — transfers STX into escrow mapping.*

* `(define-public (release-to (bounty-id uint) (recipient principal)) (response bool uint))`
  *Releases escrow funds to recipient — callable by `bounty-registry` or `arbitrator`.*

* `(define-public (refund-owner (bounty-id uint)) (response bool uint))`
  *Refunds funds back to bounty owner — callable by `bounty-registry` or `arbitrator`.*

* `(define-read-only (get-escrow-amount (bounty-id uint)) (response uint uint))`

---

## `staking.clar`

**Public functions**

* `(define-public (stake (bounty-id uint)) (response bool uint))`
  *Stake a required amount (from governance config) for this bounty. Transfers stake into contract and records mapping (bounty-id, staker) -> amount.*

* `(define-public (withdraw-stake (bounty-id uint)) (response bool uint))`
  *Withdraw stake if allowed (e.g., after owner decision or cancellation). If contributor withdraws prematurely — return `err`.*

* `(define-read-only (get-stake (bounty-id uint) (account principal)) (response uint uint))`

---

## `reputation.clar`

**Public functions**

* `(define-public (add-rep (account principal) (points uint)) (response bool uint))`
  *Internal/admin callable by `bounty-registry` to award reputation after payout.*

* `(define-read-only (get-rep (account principal)) (response uint uint))`

*(Reputation points are non-transferable.)*

---

## `badge-nft.clar`

**Public functions**

* `(define-public (mint-badge (recipient principal) (metadata (string-ascii 256))) (response (tuple (token-id uint) (ok bool)) uint))`
  *Mints a simple badge NFT to a recipient.*

* `(define-read-only (owner-of (token-id uint)) (response (option principal) uint))`

* `(define-read-only (get-token-metadata (token-id uint)) (response (option (string-ascii 256)) uint))`

*(Badge minting should be gated so only `bounty-registry` or governance can mint.)*

---

## `arbitrator.clar`

**Public functions**

* `(define-public (open-dispute (bounty-id uint) (reason (string-ascii 256))) (response bool uint))`
  *Contributor opens dispute — recorded in disputes map.*

* `(define-public (resolve-dispute (bounty-id uint) (winner enum (owner contributor) (response bool uint)))`
  *Arbitrator (admin) selects winner. If contributor wins — call `escrow.release-to`. If owner wins — `escrow.refund-owner`.*

* `(define-read-only (get-dispute (bounty-id uint)) (response (option (tuple (raiser principal) (status uint) (reason (string-ascii 256)))) uint))`

---

## `governance.clar`

**Public functions**

* `(define-public (set-fee (new-fee uint)) (response bool uint))` — admin only. Fee in basis points or micro-percent (documented in constants).
* `(define-public (set-stake-amount (new-amount uint)) (response bool uint))` — admin only.
* `(define-public (set-dispute-window (new-window uint)) (response bool uint))` — admin only.
* `(define-read-only (get-config) (response (tuple (fee uint) (stake-amount uint) (dispute-window uint)) uint))`

---

# Example flows (copy-paste friendly)

These example flows assume the contract ABIs match the API reference above. You can run these in `clarinet console` or encode them into a Clarinet test to reproduce the full happy path.

**1) Happy Path (owner posts bounty → contributor stakes → submit → owner accepts)**

1. Start console:

```bash
clarinet console
```

2. Create a bounty (owner principal is the default account in the console):

```
(contract-call? .bounty-registry create-bounty "Fix README typo" "ipfs://QmT..." u1000000 u500)
```

This returns `(ok u1)` for `bounty-id = 1`.

3. Contributor stakes (use a second principal from the seeded accounts in console):

```
(contract-call? .staking stake u1) ; ensure the contributor uses their principal
```

4. Contributor submits:

```
(contract-call? .bounty-registry submit-work u1 "ipfs://QmSubmissionHash")
```

5. Owner accepts submission:

```
(contract-call? .bounty-registry owner-accept u1 u0)
```

6. After accept:

* `escrow` releases STX to contributor,
* `reputation.add-rep` called,
* `badge-nft.mint-badge` called.

**2) Refund path (deadline passes)**

* Advance blocks beyond the `deadline` in the test harness, then call:

```
(contract-call? .bounty-registry reclaim-funds u1)
```

**3) Dispute path**

* Owner rejects. Contributor opens dispute:

```
(contract-call? .arbitrator open-dispute u1 "owner unfair rejection")
```

* Arbitrator resolves:

```
(contract-call? .arbitrator resolve-dispute u1 contributor)
```

---

# Testing plan & mapping to contracts

Each test targets flows that exercise multiple contracts. Tests are under `tests/` and use the Clarinet JS SDK.

* **bounty-tests.ts**

  * *Happy path* — covers `bounty-registry`, `escrow`, `staking`, `reputation`, `badge-nft`.
  * Asserts: escrow balance changes, contributor STX balance change, reputation increment, NFT minted.

* **escrow-tests.ts**

  * *Edge cases* — double release, insufficient funds, unauthorized calls to `escrow.release-to`.
  * Asserts: `err` returned on unauthorized calls.

* **dispute-tests.ts**

  * *Dispute resolution* — covers `bounty-registry`, `arbitrator`, `escrow`.
  * Asserts: funds end up with rightful winner after `resolve-dispute`.

* **governance-tests.ts**

  * *Admin checks* — set fee, change stake amount, unauthorized user attempt -> should `err`.

---

# Debugging & troubleshooting guide

## Common pitfalls & how to fix them

* **`clarinet check` errors (syntax)**

  * Fix type mismatches (Clarity is strongly typed).
  * Ensure tuple field names & types match `map` values and `tuple` shapes.
  * Use `map-get?` then `default-to` patterns to avoid `none` unwrap errors.

* **`contract-call?` returns `(err uXXX)`**

  * Look up `uXXX` in `utils.clar` to understand the error. Add more descriptive error codes if helpful.
  * Use `clarinet console` and `::trace` to debug a failing transaction and see the call stack. Example:

    ```
    ::trace (contract-call? .bounty-registry create-bounty "t" "ipfs" u100000 u500)
    ```

* **Failed tests due to block height / deadlines**

  * Tests can simulate block advancement. In Clarinet JS tests, you can set the block height when sending transactions or simulate timeouts by submitting additional empty blocks.

* **Inter-contract call failures**

  * Ensure the target contract function is marked `define-public`. Confirm contract identifier names are correct in `Clarinet.toml`. Use `clarinet console` to view deployed contract list.

## Useful Clarinet console commands

* Start console: `clarinet console`
* Trace a contract call: `::trace (contract-call? .contract-name fn args...)` — prints useful execution trace.
* Debug (step execution): `::debug (contract-call? .contract-name fn args...)`
* See deployed contracts & accounts printed at console start.

---

# Security considerations & limitations

* **Escrow custody**: `escrow` contract holds STX; ensure only expected contracts (registry / arbitrator) can release funds. Harden with `is-eq tx-sender` checks and contract principal checks.
* **Admin centralization**: Governance admin can change configs — document upgrade paths and consider multi-sig for production.
* **No on-chain content verification**: Submission is represented by `ipfs-hash` string only — off-chain verification is required for work quality.
* **Denial-of-service (storage)**: Do not store large strings on-chain. Use IPFS/CID references; keep on-chain strings short.
* **Reentrancy-like patterns**: Clarity is safe by design (non-turing and deterministic), but always avoid doing multiple external calls after state changes — do state updates before external calls.
* **Gas & cost**: Avoid loops and large per-call storage writes; encourage batched off-chain indexing for heavy UI operations.

---

# How to produce a meaningful Pull Request (PR checklist)

Use this checklist when drafting your PR so reviewers can focus on security, correctness, and design:

**PR Title suggestion:** `feat: initial ClariBounty MVP — registry, escrow, staking, reputation, badges, arbitrator, governance`

**PR Description template (copy/paste):**

* **What**: short summary of implemented features (list contracts + responsibilities)
* **Why**: reason and use-cases for the project
* **How to run locally**:

  * `clarinet check`
  * `clarinet test`
  * `clarinet console` for manual flows
* **Files changed**: list each contract added/modified with 1-line description
* **Testing**:

  * Number of tests
  * What they cover
  * Example test outputs (paste after running locally)
* **Security review**:

  * Items reviewed (escrow auth, admin gates)
  * Known limitations
* **Checklist**:

  * [ ] `clarinet check` passes
  * [ ] All tests pass (`clarinet test`)
  * [ ] Contracts documented with docstrings
  * [ ] Minimum of 7 `.clar` files
  * [ ] Clarity lines >= 300
  * [ ] Meaningful unit tests included
  * [ ] README and PR template included

Attach test logs in the PR body (if available) or paste them once you run the commands locally.

---

# Contribution guide & style notes

* Small, focused PRs are preferred. If you add new features, add corresponding unit tests.
* Keep contract functions short and single responsibility.
* Use `ok/err` return patterns consistently.
* Name error codes in `utils.clar` — avoid magic numbers in code.
* When writing tests, assert contract state after each important step (escrow amounts, balances, map entries, NFT ownership).

---

# Commands & developer utilities

## Count Clarity lines (verify ≥ 300 LOC)

```bash
wc -l contracts/*.clar
# Or to get just the total:
wc -l contracts/*.clar | tail -n1
```

## Count number of contracts (verify ≥ 7)

```bash
ls contracts/*.clar | wc -l
```

## Run local checks & tests

```bash
clarinet check
clarinet test
clarinet console
```