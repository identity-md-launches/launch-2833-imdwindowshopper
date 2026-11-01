# IMDwindowshopper tests

The original `IMDwindowshopper.t.sol` covers construction, metadata, CREATE2,
distribution, transfer events, basic failures, and the absence of mint/admin
entry points. `IMDwindowshopper.edges.t.sol` adds deterministic boundary cases
and eight fuzz properties, each with 1,000 runs configured in the source.

The expected supply is independently fixed at `1_000_000_000 * 10**18`. No test
mints extra tokens, edits token storage, or relies on a fork or network service.
All dependencies are the project's existing vendored Solidity libraries.

## Stateful properties

`IMDwindowshopper.invariant.t.sol` extends the original four-actor handler. Its
256 runs of 128 calls mix transfers, approvals, delegated transfers, revocations,
round trips, and five categories of rejected calls. All actors start funded;
initial approvals include both finite and infinite allowances. Only the ten
explicit handler selectors are targeted.

| Discovery pass | Property and basis | Checks |
| --- | --- | --- |
| Conservation | Constructor supply never changes; balances sum to that supply (`src/IMDwindowshopper.sol:10-15`, ERC20 `_update`) | Fixed supply and each actor's independent ledger balance after every call |
| State transitions | Approvals replace prior values; successful finite spending consumes exactly the amount; failed calls do not spend it (ERC20 `approve`, `transferFrom`, `_spendAllowance`) | Full 4-by-4 allowance model, revocation, cumulative spending, revert atomicity |
| Round trips and rounding | Ordinary transfers deliver exact minor units, including one wei; splitting a transfer cannot change its outcome (`src/IMDwindowshopper.sol:7`) | Intermediate and final balances, split-versus-single fuzz property, random round trips |
| Adversarial sequences | A spender needs the correct owner's approval; overdraws and revoked allowances cannot move value; holders retain transferability | Exact revert data, unchanged ledgers, and full-balance transfers in `afterInvariant` |
| Token properties | Self-transfers conserve balances, zero transfers preserve approvals, zero-address transfers cannot mint or burn, and only `uint256.max` is infinite (inherited ERC20 interface and implementation) | Explicit zero/one/full-supply/max/max-minus-one cases plus fuzzed inputs |

The model changes only for intended successful actions. A rejection handler may
first establish an approval so that it reaches the intended failure branch; the
failed transfer must preserve that approval. Unexpected success or an unexpected
revert reason fails the handler. `fail-on-revert = true` ensures an assertion or
unexpected handler revert cannot silently become a discarded sequence.

`afterInvariant` gathers every holder's entire balance into one actor and moves
the full supply out and back, checking transferability after the random history.
`test_HandlerBoundarySequence` also exercises these handlers deterministically.

## Reproduction

From the repository root, with the verifier's seed and build products confined
to disposable scratch space:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0xe34a0a4b0e3344bb080348d7619ec548f53f6b42ac72ca0b289f60719a03e0ee \
FOUNDRY_FUZZ_FAILURE_PERSIST_DIR=test/scratch/fuzz \
FOUNDRY_INVARIANT_FAILURE_PERSIST_DIR=test/scratch/invariant \
forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

The invariant model tracks a closed set of four actors. Transfers to the token
contract itself are covered separately by a unit test. The supplied protected
launch checks were read for their expected token behavior; their factory, pool,
and manifest harness is not part of this repository, so this local suite does
not claim to execute that integration.
