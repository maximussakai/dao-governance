# DAO Governance

A token-weighted DAO for Arc Testnet. Holders of the DAO Token (DAOT) delegate their votes, create proposals, vote, and execute passed proposals after a one day waiting period.

Built with [Arc Studio](https://studio.arc.io)

## What it does

- **Governance token (DAOT):** a fixed supply of 1,000,000 tokens, minted once to a wallet you choose at deploy. Nobody can mint more.
- **Voting:** anyone can create a proposal. Voting opens 60 seconds later and lasts 10 minutes. A proposal passes when at least 4% of the supply takes part and more votes are For than Against.
- **Timelock:** a passed proposal waits one day before anyone can execute it.
- **No admin:** there are no admin keys, no pause, and no upgrade path. Changes only happen through passed proposals.

The voting window is short on purpose so it is easy to try out. A passed proposal can change it.

Before voting, token holders must delegate their votes to themselves (or to someone else).

## Tech stack

- Solidity 0.8.28, OpenZeppelin Contracts 5.6.1
- Foundry for build and tests
- Vite, React and TypeScript starter app (no DAO interface yet)

## Project layout

- `contracts/DAOToken.sol`: the governance token
- `contracts/DAOGovernor.sol`: the governor, which creates its own timelock
- `contracts/DAOGovernor-design.md`: the design doc
- `contracts/test/`: Foundry tests

## Development

Prerequisites: [Foundry](https://book.getfoundry.sh/) and [Bun](https://bun.sh).

```bash
bun install
bun run contracts:build
bun run contracts:test
```

Deploying (Arc Testnet): deploy `DAOToken` with the name, symbol, the wallet that receives the supply, and `1000000000000000000000000` as the supply. Then deploy `DAOGovernor` with a name, the token address, `60`, `600`, `0`, `4`, `86400`.

### Environment variables

None.
