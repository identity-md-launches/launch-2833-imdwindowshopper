// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDwindowshopper} from "../src/IMDwindowshopper.sol";

/// @dev All supply stays within these four actors. A separate model tracks each balance and allowance.
contract TokenHandler is Test {
    IMDwindowshopper public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(IMDwindowshopper token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder", vm.toString(i)));
        }
        expectedBalance[actors[0]] = token_.totalSupply();
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // An approval may exceed the entire supply; only MAX has infinite semantics.
        amount = unlimited ? type(uint256).max : bound(amount, 0, type(uint256).max - 1);
        _approve(owner, spender, amount);
    }

    function spend(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[from][spender];
        uint256 available = expectedBalance[from] < allowed ? expectedBalance[from] : allowed;
        amount = bound(amount, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[from][spender] -= amount;
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, 0);
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    function rejectOverspend(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        _expectFailure(
            from,
            abi.encodeCall(token.transfer, (to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function rejectUnapprovedSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Reach the exact allowance+1 boundary, even when the previous approval was infinite.
        amount = bound(amount, 1, type(uint256).max);
        _approve(owner, spender, amount - 1);
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, amount - 1, amount)
        );
    }

    function rejectUnfundedSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
        // Invariants check the unchanged model, including any allowance spent before the revert.
    }

    function rejectZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        bytes memory reason = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            _approve(owner, spender, amount);
            _expectFailure(spender, abi.encodeCall(token.transferFrom, (owner, address(0), amount)), reason);
        } else {
            _expectFailure(owner, abi.encodeCall(token.transfer, (address(0), amount)), reason);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        _expectFailure(
            owner,
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        assertEq(token.allowance(owner, address(0)), 0);
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = expectedBalance[from];
        uint256 toBefore = expectedBalance[to];
        amount = bound(amount, 0, fromBefore);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        // The model stays unchanged: an exact round trip has zero net effect, including self-transfers.
        assertEq(token.balanceOf(from), fromBefore);
        assertEq(token.balanceOf(to), toBefore);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _expectFailure(address caller, bytes memory data, bytes memory reason) internal {
        vm.prank(caller);
        (bool success, bytes memory returned) = address(token).call(data);
        assertFalse(success, "invalid operation unexpectedly succeeded");
        assertEq(returned, reason, "unexpected revert reason");
        // Never catch handler assertions: fail_on_revert makes any harness failure fail the campaign.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract IMDwindowshopperInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    IMDwindowshopper internal token;
    TokenHandler internal handler;

    function setUp() public {
        token = new IMDwindowshopper();
        handler = new TokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));
        // Start with funded actors and both approval modes, so delegated transfers are useful immediately.
        for (uint256 i = 1; i < 4; ++i) {
            handler.move(0, i, SUPPLY / 4);
        }
        for (uint256 i; i < 4; ++i) {
            handler.approve(i, (i + 1) % 4, SUPPLY / 4, i % 2 == 0);
        }
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = TokenHandler.move.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.spend.selector;
        selectors[3] = TokenHandler.revoke.selector;
        selectors[4] = TokenHandler.rejectOverspend.selector;
        selectors[5] = TokenHandler.rejectUnapprovedSpend.selector;
        selectors[6] = TokenHandler.rejectUnfundedSpend.selector;
        selectors[7] = TokenHandler.rejectZeroReceiver.selector;
        selectors[8] = TokenHandler.rejectZeroSpender.selector;
        selectors[9] = TokenHandler.roundTrip.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyAndBalancesMatchModel() public view {
        uint256 held;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            held += balance;
        }
        assertEq(held, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_AllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
        }
    }

    function invariant_MetadataRemainsFixed() public view {
        assertEq(token.name(), "IMDwindowshopper");
        assertEq(token.symbol(), "WWW");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    function afterInvariant() public {
        // Regardless of the random history, every actor can still transfer its whole balance.
        for (uint256 i = 1; i < 4; ++i) {
            handler.move(i, 0, handler.expectedBalance(handler.actors(i)));
            assertEq(token.balanceOf(handler.actors(i)), 0);
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        handler.roundTrip(0, 1, SUPPLY);
        invariant_SupplyAndBalancesMatchModel();
        invariant_AllowancesMatchModel();
    }

    function test_HandlerBoundarySequence() public {
        // Pin difficult branches as well as letting the invariant runner discover random sequences.
        handler.rejectOverspend(0, 0, type(uint256).max);
        handler.rejectUnapprovedSpend(0, 1, type(uint256).max);
        handler.rejectUnfundedSpend(0, 1, type(uint256).max, false);
        handler.rejectUnfundedSpend(0, 1, type(uint256).max, true);
        handler.rejectZeroReceiver(0, 1, 0, false);
        handler.rejectZeroReceiver(0, 1, 0, true);
        handler.rejectZeroSpender(0, 0);
        handler.approve(0, 1, 0, true);
        handler.revoke(0, 1);
        handler.approve(0, 1, type(uint256).max - 1, false);
        handler.spend(0, 1, 1, 1);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), type(uint256).max - 2);
        handler.roundTrip(1, 2, 1);
        invariant_SupplyAndBalancesMatchModel();
        invariant_AllowancesMatchModel();
        afterInvariant();
    }
}
