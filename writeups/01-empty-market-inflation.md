# 01: Empty-Market Inflation (Donation) Attack

| | |
|---|---|
| **Severity** | High |
| **Bug class** | Share price manipulation / rounding |
| **Affects** | ERC4626-style vaults, Compound v2 forks (cTokens), any share-based pool priced from its raw token balance |
| **Real-world losses** | Hundred Finance (Apr 2023, Optimism, ~$7.4M), Sonne Finance (May 2024, Optimism, ~$20M) |
| **PoC** | [`test/01-empty-market-inflation/EmptyMarketInflation.t.sol`](../test/01-empty-market-inflation/EmptyMarketInflation.t.sol) |

## Summary

When a share-based vault prices its shares from its live token balance, an attacker can take over an
empty vault: deposit a dust amount to own the only share, then transfer tokens directly into the vault
to inflate that share's price. The next honest deposit rounds down to zero shares, and the attacker
redeems their single share for everything in the vault, including the victim's deposit.

## Real-world incidents

- **Hundred Finance (April 2023, Optimism, ~$7.4M).** A Compound v2 fork. The attacker used a flash loan
  to donate into an empty hToken market, skewing its exchange rate, and combined this with a rounding
  error in redeeming underlying to drain the protocol's lending pools.
- **Sonne Finance (May 2024, Optimism, ~$20M).** Also a Compound v2 fork. Sonne's normal safeguard was to
  list new markets at 0% collateral factor, seed and burn a small deposit, and only then raise the
  collateral factor. For the new VELO markets, the collateral factor changes executed through a
  timelock that anyone could trigger, so the attacker executed them before the markets were seeded and
  ran the known donation attack against the still-empty markets. About $6.5M was saved.

The PoC in this repo isolates the shared root cause in a minimal vault. The real attacks added extra
steps (flash loans, borrowing against the inflated collateral) to turn the broken exchange rate into a
drain of the protocol's other markets.

## Root cause

Three properties combine:

1. **Share price comes from the raw balance.** `totalAssets()` returns `asset.balanceOf(address(this))`,
   so anyone can change the share price by transferring tokens in without minting shares.
2. **Share math rounds down.** `shares = assets * totalSupply / totalAssets`.
3. **Zero-share deposits are accepted.** Nothing stops a deposit that mints 0 shares.

```solidity
function totalAssets() public view returns (uint256) {
    return asset.balanceOf(address(this)); // can be inflated by a direct transfer
}

function deposit(uint256 assets) external returns (uint256 shares) {
    shares = convertToShares(assets); // rounds down, can be 0
    // missing: if (shares == 0) revert ZeroShares();
    if (!asset.transferFrom(msg.sender, address(this), assets)) revert TransferFailed();
    ...
}
```

## Attack walkthrough

Numbers taken from the passing PoC:

| Step | Action | Vault balance | Total shares | Result |
|---|---|---|---|---|
| 1 | Attacker deposits 1 wei into the empty vault | 1 wei | 1 | Attacker owns 100% of shares |
| 2 | Attacker transfers 10,000 tokens directly to the vault | 10,000 + 1 wei | 1 | 1 share is now worth 10,000 + 1 wei |
| 3 | Victim deposits 10,000 tokens | 20,000 + 1 wei | 1 | `10,000e18 * 1 / (10,000e18 + 1)` rounds to **0 shares** |
| 4 | Attacker redeems their 1 share | 0 | 0 | Attacker receives 20,000 + 1 wei |

Attacker spent 10,000 + 1 wei and received 20,000 + 1 wei: **profit = 10,000 tokens, the victim's entire
deposit.** The victim holds 0 shares and cannot recover anything.

## Impact

Total loss of funds for the first depositors into any new or emptied vault or market. In lending
protocols the damage is larger: the inflated share can be used as collateral to borrow from every other
market, which is how the Hundred Finance and Sonne Finance attacks reached millions.

## Recommended fixes

Any of these blocks the attack; strong designs use more than one.

1. **Virtual shares and assets** (OpenZeppelin ERC4626's approach, implemented in
   [`FixedVault.sol`](../src/01-empty-market-inflation/FixedVault.sol)). Compute prices as
   `(totalAssets + 1) / (totalSupply + 10^offset)`. The virtual shares absorb most of any donation, so
   the attacker loses money. In the PoC, the same 10,000-token attack returns the attacker only ~5,000
   while the victim recovers 99.99997% of their deposit.
2. **Reject zero-share deposits.** `if (shares == 0) revert ZeroShares();` so a victim is never silently
   paid nothing.
3. **Seed every new market before it goes live.** Deposit a small amount and burn the shares (send them to
   a dead address) in the same transaction that creates the market, so it is never empty. Make sure the
   steps that enable the market cannot run before seeding, which is the gap Sonne's attacker used.
4. **Track deposits internally** instead of reading `balanceOf`, so direct transfers do not move the price.

## Proof of concept

```bash
forge test --match-path "test/01-empty-market-inflation/*" -vv
```

| Test | What it proves |
|---|---|
| `test_exploit_victimLosesEntireDeposit` | The attack steals the victim's full deposit from the vulnerable vault |
| `test_fix_attackBecomesUnprofitable` | Against the fixed vault the attacker loses money and the victim keeps their funds |
| `test_fix_zeroShareDepositReverts` | A deposit that would round to zero shares reverts instead of losing the victim's tokens |
| `testFuzz_fix_attackerNeverProfits` | Across 1,000 random donation and deposit sizes, the attacker never profits on the fixed vault |
| `test_fix_normalDepositAndRedeemStillWork` | The fix does not break normal deposits and withdrawals |

## References

- Halborn, [Explained: The Hundred Finance Hack (April 2023)](https://halborn.com/blog/post/explained-the-hundred-finance-hack-april-2023)
- Sonne Finance, [Post-mortem: Sonne Finance Exploit](https://medium.com/@SonneFinance/post-mortem-sonne-finance-exploit-12f3daa82b06)
- Verichains, [Compound V2 Forked Vulnerability: $20M Sonne Finance Hack](https://blog.verichains.io/p/compound-v2-forked-vulnerability)
- OpenZeppelin, ERC4626 virtual shares and the inflation attack (ERC4626 documentation)
