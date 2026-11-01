// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDwindowshopper} from "../src/IMDwindowshopper.sol";

/// @dev Test-only factory: checks CREATE2 deployment and exact outbound distribution.
contract TokenDeploymentProbe {
    function deploy(bytes32 salt) external returns (IMDwindowshopper) {
        return new IMDwindowshopper{salt: salt}();
    }

    function move(IMDwindowshopper token, address to, uint256 amount) external {
        require(token.transfer(to, amount), "transfer failed");
    }
}

contract IMDwindowshopperTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    IMDwindowshopper internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    function setUp() public {
        token = new IMDwindowshopper();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "IMDwindowshopper");
        assertEq(token.symbol(), "WWW");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsMintEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), address(this), SUPPLY);
        new IMDwindowshopper();
    }

    function test_Create2MintsToImmediateFactoryInsteadOfTransactionOrigin() public {
        TokenDeploymentProbe factory = new TokenDeploymentProbe();
        bytes32 salt = keccak256("WWW deployment test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(IMDwindowshopper).creationCode)
                        )
                    )
                )
            )
        );

        vm.prank(alice, alice);
        IMDwindowshopper deployed = factory.deploy(salt);

        assertEq(address(deployed), predicted);
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function test_DistributionAndClaimTransfersDeliverExactAmounts() public {
        TokenDeploymentProbe factory = new TokenDeploymentProbe();
        IMDwindowshopper deployed = factory.deploy(keccak256("distribution test"));
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");
        address requester = makeAddr("requester");

        factory.move(deployed, distributor, SUPPLY / 10);
        factory.move(deployed, pool, SUPPLY * 7 / 10);
        factory.move(deployed, requester, SUPPLY / 5);
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.balanceOf(distributor), SUPPLY / 10);
        assertEq(deployed.balanceOf(pool), SUPPLY * 7 / 10);
        assertEq(deployed.balanceOf(requester), SUPPLY / 5);

        vm.prank(distributor);
        assertTrue(deployed.transfer(alice, SUPPLY / 10));
        assertEq(deployed.balanceOf(distributor), 0);
        assertEq(deployed.balanceOf(alice), SUPPLY / 10);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 42 ether);
        assertTrue(token.transfer(alice, 42 ether));
        assertEq(token.balanceOf(alice), 42 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 42 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireSupplyCanMoveAndMoveBack() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsEventAndCanBeReplacedAndRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 100 ether);
        assertTrue(token.approve(spender, 100 ether));
        assertEq(token.allowance(address(this), spender), 100 ether);
        assertTrue(token.approve(spender, 40 ether));
        assertEq(token.allowance(address(this), spender), 40 ether);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), bob, 1);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromConsumesFiniteAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(spender, 100 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 60 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 60 ether));
        assertEq(token.allowance(address(this), spender), 40 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 60 ether);
        assertEq(token.balanceOf(alice), 60 ether);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 40 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 40 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowanceIsNotDecremented() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
    }

    function test_TransferFromSelfStillRequiresAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToSelfConsumesAllowanceWithoutChangingBalance() public {
        assertTrue(token.approve(spender, 10 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_FailedTransferFromRestoresAllowanceAndBalances() public {
        assertTrue(token.transfer(alice, 5 ether));
        vm.prank(alice);
        assertTrue(token.approve(spender, 10 ether));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 6 ether));
        token.transferFrom(alice, bob, 6 ether);
        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromToZeroRevertsAndRestoresAllowance() public {
        assertTrue(token.approve(spender, 10 ether));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalCannotBeUsedByAnotherSpender() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_DeployerCannotTakeBackHolderTokens() public {
        assertTrue(token.transfer(alice, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 10 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_NoMintBurnFreezeOrUpgradeEntryPoints() public {
        assertTrue(token.transfer(alice, 10 ether));
        bytes[] memory attempts = new bytes[](10);
        attempts[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether);
        attempts[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        attempts[2] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        attempts[3] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        attempts[4] = abi.encodeWithSignature("pause()");
        attempts[5] = abi.encodeWithSignature("blacklist(address)", alice);
        attempts[6] = abi.encodeWithSignature("freeze(address)", alice);
        attempts[7] = abi.encodeWithSignature("transferOwnership(address)", bob);
        attempts[8] = abi.encodeWithSignature("upgradeTo(address)", bob);
        attempts[9] = abi.encodeWithSignature("initialize(address)", bob);

        for (uint256 i; i < attempts.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(attempts[i]);
            assertFalse(deployerSucceeded);
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(attempts[i]);
            assertFalse(strangerSucceeded);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_NativeCurrencyIsRejected() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferMoreThanBalanceReverts(uint256 funded, uint256 excess) public {
        funded = bound(funded, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - funded);
        assertTrue(token.transfer(alice, funded));
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, funded, funded + excess)
        );
        token.transfer(bob, funded + excess);
        assertEq(token.balanceOf(alice), funded);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromConservesSupplyAndAllowance(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromMoreThanAllowanceReverts(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        token.transferFrom(address(this), alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), approved);
    }
}
