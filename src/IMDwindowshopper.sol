// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title IMDwindowshopper (WWW)
/// @notice A fixed supply of one billion tokens, with 18 decimals and ordinary ERC-20 transfers.
contract IMDwindowshopper is ERC20 {
    /// @notice The entire supply in the smallest token units (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the immediate deployer.
    /// @dev When deployed by the launch factory, the factory receives all tokens for distribution.
    constructor() ERC20("IMDwindowshopper", "WWW") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
