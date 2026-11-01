# Vendored dependencies

Dependencies are checked in as ordinary source and license files. No dependency
manager, Git submodule, network fetch, or compiler binary is part of the build.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | `v5.0.2` | ERC-20 and its complete import closure in `lib/openzeppelin-contracts/contracts/` | `lib/openzeppelin-contracts/LICENSE` (MIT) |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` | Upstream `src/` in `lib/forge-std/src/`; test-only | `lib/forge-std/LICENSE-MIT` and `LICENSE-APACHE` (MIT or Apache-2.0) |

These files were copied without source modifications from the release archives:

| Archive | SHA-256 |
| --- | --- |
| `https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2` | `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a` |
| `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7` | `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94` |

The OpenZeppelin subset consists of `ERC20.sol`, `IERC20.sol`,
`IERC20Metadata.sol`, `Context.sol`, and `draft-IERC6093.sol`. Paths are preserved
for relative imports. Only source and license files are vendored; upstream
repository configuration, tests, and package-management files are omitted.

The compiler is selected by version in `foundry.toml`. The verification runtime
provides Solidity 0.8.26; it is not vendored or selected by a local binary path.
