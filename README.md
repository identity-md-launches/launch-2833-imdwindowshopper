# IMDwindowshopper (WWW)

A fixed-supply ERC-20 for the IdentityMD custom-token launch. The deployable
contract is [`IMDwindowshopper`](src/IMDwindowshopper.sol), built on the vendored
OpenZeppelin Contracts v5.0.2 ERC-20 implementation.

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity artifact | `src/IMDwindowshopper.sol:IMDwindowshopper` |
| Token name | `IMDwindowshopper` |
| Symbol | `WWW` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Deployment ETH value | `0` |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Intended launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | `none` |

`INITIAL_SUPPLY` is the named constant for the smallest-unit supply. The
constructor mints it once and emits `Transfer(address(0), deployer, INITIAL_SUPPLY)`.
The default ERC-20 decimal count is 18. There are no constructor calls to outside
contracts, external libraries to link, or initialization transactions.

When the launch factory creates this contract, the factory receives the **entire**
supply, independently of the transaction origin. Direct deployment gives the
supply to that direct deployer instead. Deployment tooling must therefore create
the token from the intended factory; an intermediate helper would receive the
supply itself.

## Behavior and assumptions

- Ordinary ERC-20 transfers deliver the requested amount without tax, burn, or
  rebasing. Zero-amount transfers to a valid address succeed and emit `Transfer`.
  Transfers to the zero address revert. Self-transfers preserve balances.
- `approve` sets or replaces the caller's allowance and emits `Approval`.
  `transferFrom` requires the caller's allowance, even when the caller is also
  the holder, and consumes finite allowances. Maximum `uint256` approval remains
  unchanged when spent. OpenZeppelin v5 does not emit `Approval` when spending an
  allowance; integrations should query `allowance` for its current value.
- Invalid operations revert with OpenZeppelin ERC-6093 custom errors. A failed
  transfer restores all state, including any attempted allowance decrement.
- There is no owner or administrative role, mint or burn entry point, pause,
  blacklist, seizure, upgrade, permit, or proxy. The deployer has no special
  authority after receiving the initial supply. The supply remains exactly
  `10^27` for the lifetime of this deployed contract.
- The token performs no external calls during transfers or approvals and has no
  oracle, randomness, timer, or network service dependency.
- The contract has no payable entry point or asset recovery function. Sending
  tokens to the token contract itself can leave them permanently inaccessible.
  Holders are responsible for recipient addresses and spender approvals.

## After launch

There are no settings or owner-only setters to configure, and no keeper or admin
account to operate. Holders can immediately transfer and approve tokens.

The IdentityMD launch process prepares the manifest, deploys the artifact, and
distributes the factory-held supply according to the provided launch economics:
10% to the swarm distributor, 70% to pool seeding, and 20% to the requester's
specified remainder recipient. Those actions and pool configuration belong to
the factory and launch process; the token constructor makes no allocations or
pool calls. No `launch.json` or application contract is included in this project.

The launch operator is responsible for confirming the artifact, factory address,
initial supply, launch distribution, and deployed source verification. An
independent adversarial review belongs to the release process. This assignment
does not deploy or broadcast transactions.

## Build and test

From the repository root, with Foundry and Solidity 0.8.26 available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xe34a0a4b0e3344bb080348d7619ec548f53f6b42ac72ca0b289f60719a03e0ee forge test
forge fmt --check
```

All Solidity dependencies and their licenses are ordinary files in `lib/`; no
submodules or dependency downloads are needed to build or test. See
[`DEPENDENCIES.md`](DEPENDENCIES.md) for pinned versions and archive checksums.
The configuration enables neither FFI nor filesystem cheatcode permissions.
Tests use no RPC, secrets, environment reads, or shared external state. The seed
above is passed to Foundry itself, not read by a Solidity test.

The suite includes 22 deterministic tests and four fuzz tests (512 cases each),
plus two stateful invariants checked together across 128 sequences of 64 calls:

- Metadata, constructor mint event, initial supply, and CREATE2 factory receipt.
- Exact 10%/70%/20% distribution and distributor-to-holder transfers.
- Full, partial, self, and zero transfers; approvals, replacement, and revocation;
  finite and infinite allowances; delegated transfers and emitted events.
- Insufficient balances and allowances, invalid recipients and spenders,
  allowance isolation, failed-transfer rollback, and rejected admin calls.
- Independent balance and allowance models across random multi-holder transfers,
  approvals, and delegated transfers, with total-supply conservation.

The distribution test models token movement. It does not run a real Uniswap pool
or the external launch harness: the supplied protected tests depend on launch
infrastructure, manifest-derived inputs, and contracts outside this repository.
Those checks remain the launch verifier's responsibility.

## Local review

The implementation review checked that `_mint` is reached only by the
constructor, transfer authorization stays in the unchanged ERC-20 implementation,
and no reachable admin or upgrade path is introduced. Successful and failed
transfers and allowance spending are tested against exact balances and errors.
Foundry build, seeded tests, and formatting checks were run with the pinned
compiler. Slither, Mythril, and an independent security audit were not run here.
