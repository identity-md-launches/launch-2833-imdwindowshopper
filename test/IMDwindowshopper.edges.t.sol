// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDwindowshopper} from "src/IMDwindowshopper.sol";

/// @dev Complements the original tests with arithmetic boundaries and approval lifecycle properties.
/// forge-config: default.fuzz.runs = 1000
contract IMDwindowshopperEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    uint256 internal constant MAX = type(uint256).max;
    IMDwindowshopper internal token;
    address internal holder;
    address internal recipient;
    address internal spender;

    function setUp() public {
        holder = makeAddr("edge holder");
        recipient = makeAddr("edge recipient");
        spender = makeAddr("edge spender");
        token = new IMDwindowshopper();
        assertTrue(token.transfer(holder, SUPPLY));
    }

    function test_OneWeiCanMoveAndReturnWithoutRounding() public {
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 1));
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, 1));
        _assertBalances(SUPPLY, 0);
    }

    function test_MaximumTransferRevertsWithBalanceError() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, MAX));
        vm.prank(holder);
        token.transfer(recipient, MAX);
        _assertBalances(SUPPLY, 0);
    }

    function test_MaximumTransferFromRevertsEvenWithInfiniteApproval() public {
        _approve(MAX);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, MAX));
        vm.prank(spender);
        token.transferFrom(holder, recipient, MAX);
        assertEq(token.allowance(holder, spender), MAX);
        _assertBalances(SUPPLY, 0);
    }

    function test_AlmostMaximumApprovalIsFinite() public {
        _approve(MAX - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), MAX - 2);
        _assertBalances(SUPPLY - 1, 1);
    }

    function test_InfiniteApprovalCanBeRevokedAndReplacedWithFiniteApproval() public {
        _approve(MAX);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), MAX);

        _approve(0);
        _expectNoAllowance();
        _approve(1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        _expectNoAllowance();
        _assertBalances(SUPPLY - 2, 2);
    }

    function test_ExhaustedApprovalDoesNotReviveWhenTokensReturn() public {
        _approve(SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, SUPPLY));
        assertEq(token.allowance(holder, spender), 0);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, SUPPLY));
        _expectNoAllowance();
        _assertBalances(SUPPLY, 0);
    }

    function test_UnfundedOwnerCanApproveThenSpendOnlyAfterReceivingTokens() public {
        vm.prank(recipient);
        assertTrue(token.approve(spender, MAX - 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, recipient, 0, 1));
        vm.prank(spender);
        token.transferFrom(recipient, holder, 1);
        assertEq(token.allowance(recipient, spender), MAX - 1);
        _assertBalances(SUPPLY, 0);

        vm.prank(holder);
        assertTrue(token.transfer(recipient, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(recipient, holder, 1));
        assertEq(token.allowance(recipient, spender), MAX - 2);
        _assertBalances(SUPPLY, 0);
    }

    function test_SelfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, SUPPLY + 1)
        );
        vm.prank(holder);
        token.transfer(holder, SUPPLY + 1);
        _assertBalances(SUPPLY, 0);
    }

    function test_DelegatedSelfTransferStillRequiresSufficientBalance() public {
        _approve(SUPPLY + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, SUPPLY + 1)
        );
        vm.prank(spender);
        token.transferFrom(holder, holder, SUPPLY + 1);
        assertEq(token.allowance(holder, spender), SUPPLY + 1);
        _assertBalances(SUPPLY, 0);
    }

    function test_ZeroTransfersLeaveEveryApprovalModeUntouched() public {
        uint256[4] memory approvals = [uint256(0), uint256(1), MAX - 1, MAX];
        for (uint256 i; i < approvals.length; ++i) {
            _approve(approvals[i]);
            vm.expectEmit(true, true, false, true, address(token));
            emit IERC20.Transfer(holder, recipient, 0);
            vm.prank(spender);
            assertTrue(token.transferFrom(holder, recipient, 0));
            assertEq(token.allowance(holder, spender), approvals[i]);
            _assertBalances(SUPPLY, 0);
        }
    }

    function test_ZeroDelegatedTransferToZeroStillReverts() public {
        _approve(1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        assertEq(token.allowance(holder, spender), 1);
        _assertBalances(SUPPLY, 0);
    }

    function test_ZeroApprovalToZeroSpenderStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(holder);
        token.approve(address(0), 0);
        assertEq(token.allowance(holder, address(0)), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_TransferFromZeroSourceCannotMintEvenForZeroAmount() public {
        // Both calls are invalid. Do not prescribe which of the sender/approval checks runs first.
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), recipient, 0);
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), recipient, 1);
        assertEq(token.allowance(address(0), spender), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_TransferToTokenContractDoesNotBurn() public {
        vm.prank(holder);
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testFuzz_SplitTransfersEqualOneTransfer(uint256 amount, uint256 first) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        IMDwindowshopper single = new IMDwindowshopper();
        assertTrue(single.transfer(recipient, amount));
        vm.startPrank(holder);
        assertTrue(token.transfer(recipient, first));
        assertTrue(token.transfer(recipient, amount - first));
        vm.stopPrank();
        assertEq(token.balanceOf(recipient), single.balanceOf(recipient));
        assertEq(token.balanceOf(holder), single.balanceOf(address(this)));
        _assertBalances(SUPPLY - amount, amount);
    }

    function testFuzz_RoundTripRestoresAlreadyFundedParticipants(uint256 starting, uint256 amount) public {
        starting = bound(starting, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY - starting);
        vm.startPrank(holder);
        assertTrue(token.transfer(recipient, starting));
        assertTrue(token.transfer(recipient, amount));
        vm.stopPrank();
        _assertBalances(SUPPLY - starting - amount, starting + amount);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, amount));
        _assertBalances(SUPPLY - starting, starting);
    }

    function testFuzz_ApprovalOverwriteIsIdempotentAndIsolated(uint256 first, uint256 replacement) public {
        _approve(first);
        vm.prank(recipient);
        assertTrue(token.approve(spender, first));
        for (uint256 i; i < 2; ++i) {
            vm.expectEmit(true, true, false, true, address(token));
            emit IERC20.Approval(holder, spender, replacement);
            _approve(replacement);
            assertEq(token.allowance(holder, spender), replacement);
            assertEq(token.allowance(recipient, spender), first);
            assertEq(token.allowance(holder, recipient), 0);
            assertEq(token.allowance(spender, holder), 0);
            _assertBalances(SUPPLY, 0);
        }
    }

    function testFuzz_FiniteAllowanceTracksCumulativeSpending(uint256 approved, uint256 first, uint256 second) public {
        approved = bound(approved, 0, MAX - 1);
        uint256 available = approved < SUPPLY ? approved : SUPPLY;
        first = bound(first, 0, available);
        second = bound(second, 0, available - first);
        _approve(approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, first));
        assertEq(token.allowance(holder, spender), approved - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, second));
        uint256 remaining = approved - first - second;
        assertEq(token.allowance(holder, spender), remaining);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, remaining, remaining + 1)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, remaining + 1);
        assertEq(token.allowance(holder, spender), remaining);
        _assertBalances(SUPPLY - first - second, first + second);
    }

    function testFuzz_BalanceFailureRestoresFiniteAllowance(uint256 funded, uint256 attempted) public {
        funded = bound(funded, 0, SUPPLY);
        attempted = bound(attempted, funded + 1, MAX - 1);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, funded));
        vm.prank(recipient);
        assertTrue(token.approve(spender, attempted));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, recipient, funded, attempted)
        );
        vm.prank(spender);
        token.transferFrom(recipient, holder, attempted);
        assertEq(token.allowance(recipient, spender), attempted);
        _assertBalances(SUPPLY - funded, funded);
    }

    function testFuzz_ZeroReceiverFailurePreservesApproval(uint256 amount, uint256 approved, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        approved = unlimited ? MAX : bound(approved, amount, MAX - 1);
        _approve(approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), amount);
        assertEq(token.allowance(holder, spender), approved);
        _assertBalances(SUPPLY, 0);
    }

    function testFuzz_SelfTransfersPreserveBalanceButConsumeFiniteAllowance(uint256 amount, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(holder);
        assertTrue(token.transfer(holder, amount));
        _assertBalances(SUPPLY, 0);
        _approve(unlimited ? MAX : amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, amount));
        assertEq(token.allowance(holder, spender), unlimited ? MAX : 0);
        _assertBalances(SUPPLY, 0);
    }

    function testFuzz_AllowanceCannotBeBorrowedFromAnotherOwner(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, amount));
        _approve(amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount));
        vm.prank(spender);
        token.transferFrom(recipient, spender, amount);
        assertEq(token.allowance(holder, spender), amount);
        assertEq(token.allowance(recipient, spender), 0);
        _assertBalances(SUPPLY - amount, amount);
    }

    function _approve(uint256 amount) internal {
        vm.prank(holder);
        assertTrue(token.approve(spender, amount));
    }

    function _expectNoAllowance() internal {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 0);
    }

    function _assertBalances(uint256 held, uint256 received) internal view {
        assertEq(token.balanceOf(holder), held);
        assertEq(token.balanceOf(recipient), received);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(held + received, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
