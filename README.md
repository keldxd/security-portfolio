# Smart Contract Security Portfolio

Proofs of concept, writeups and fixes for smart contract vulnerabilities, by **Kelvin Mwangi**,
smart contract security researcher (Nairobi, remote).

Every entry follows the same structure an audit finding would: the vulnerable code, a working exploit,
the fix, and tests proving the fix holds. All PoCs are written in [Foundry](https://getfoundry.sh) and run
locally.

## Writeups

| # | Vulnerability | Severity | Real-world incidents | Writeup |
|---|---|---|---|---|
| 01 | Empty-market inflation (donation) attack | High | Hundred Finance (2023), Sonne Finance (2024) | [Read](writeups/01-empty-market-inflation.md) |

## Running the PoCs

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
git clone https://github.com/keldxd/security-portfolio.git
cd security-portfolio
forge install
forge test -vv
```

Run a single entry:

```bash
forge test --match-path "test/01-empty-market-inflation/*" -vv
```

## Layout

```
src/<entry>/        vulnerable and fixed contracts
test/<entry>/       exploit PoC and fix tests
writeups/           one markdown writeup per entry
```

## Disclaimer

The vulnerable contracts in this repository are intentionally insecure and exist for education only.
Do not deploy them. Live-contest findings are only published after judging and with the platform's
disclosure permission.
