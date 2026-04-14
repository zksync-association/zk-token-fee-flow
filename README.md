# ZKsync Fee Flow

A system for managing fee token auctions and distribution on ZKsync Era.

## Overview

This repository contains two main contracts:

- **FeeFlow**: A fixed-price auction contract where bidders exchange ZK tokens for accumulated fee assets.
- **Splitter**: A contract that splits received ZK tokens between burning and distributing to configured recipients.

## Architecture

```
                    ┌─────────────┐
                    │   Claimer   │
                    └──────┬──────┘
                           │ ZK tokens
                           ▼
                    ┌─────────────┐
                    │   FeeFlow   │ ◄── Fee tokens accumulate here
                    └──────┬──────┘
                           │ ZK tokens
                           ▼
                    ┌─────────────┐
                    │   Splitter  │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
           🔥 Burn    Distributor1  Distributor2
```

## Installation

```bash
# Clone the repository
git clone https://github.com/ScopeLift/zksync-fee-flow.git
cd zksync-fee-flow

# Install dependencies
forge install
```

## Building

```bash
forge build
```

## Testing

This project uses [foundry-zksync](https://github.com/matter-labs/foundry-zksync) for ZKsync Era compatibility.

### Tests

Run unit and integration tests (mock-based, fast):

```bash
forge test
```

### Test Profiles

- `default`: Standard test runs
- `lite`: Optimizer disabled for faster compilation during development
- `ci`: Extended fuzz/invariant runs for CI

```bash
# Run with lite profile for faster iteration
FOUNDRY_PROFILE=lite forge test

# Run with CI profile for thorough testing
FOUNDRY_PROFILE=ci forge test
```

## Formatting

This project uses [scopelint](https://github.com/ScopeLift/scopelint) for formatting:

```bash
scopelint fmt      # Format files
scopelint check    # Check formatting
```

## Deployment

The deployment script is located at `script/Deploy.s.sol`. It deploys both Splitter and FeeFlow contracts with UUPS proxies.

## Security

Please report any security issues to security@matterlabs.dev.

## License

MIT
