
# [jyh] DeFi Stablecoin

This is a project for creating a stablecoin where users can deposit WETH and WBTC in exchange for a token pegged to the USD.

- [About](#about)
- [Getting Started](#getting-started)
  - [Requirements](#requirements)
  - [Quickstart](#quickstart)
    - [Optional Gitpod](#optional-gitpod)
- [Updates](#updates)
- [Usage](#usage)
  - [Start a local node](#start-a-local-node)
  - [Deploy](#deploy)
  - [Deploy - Other Network](#deploy---other-network)
  - [Testing](#testing)
    - [Test Coverage](#test-coverage)
- [Deployment to a testnet or mainnet](#deployment-to-a-testnet-or-mainnet)
  - [Scripts](#scripts)
  - [Estimate gas](#estimate-gas)
- [Formatting](#formatting)
- [Slither](#slither)
- [Additional Info:](#additional-info)
  - [Let's talk about what "Official" means](#lets-talk-about-what-official-means)
  - [Summary](#summary)
- [Thank you!](#thank-you)

# About

This project is designed to be a stablecoin where users can deposit WETH and WBTC in exchange for a token that will be pegged to the USD.

# Getting Started

## Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You can verify your installation by running `git --version`, which should return a response like `git version x.x.x`.
- [foundry](https://getfoundry.sh/)
  - You can verify your installation by running `forge --version`, which should return a response like `forge 0.2.0 (816e00b 2023-03-16T00:05:26.396218Z)`.

## Quickstart

```bash
git clone https://github.com/JinYuhui367/foundry-defi-stablecoin-f24.git
cd foundry-defi-stablecoin-f24
forge build
```

### Optional Gitpod

If you prefer not to run and install locally, you can work with this repo in Gitpod. If you do this, you can skip the `clone this repo` part.

[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#github.com/YourUsername/personal-defi-stablecoin)

# Updates

- The latest version of openzeppelin-contracts has changes in the ERC20Mock file. To follow along, you need to install version 4.8.3, which can be done by running `forge install openzeppelin/openzeppelin-contracts@v4.8.3 --no-commit` instead of `forge install openzeppelin/openzeppelin-contracts --no-commit`.

# Usage

## Start a local node

```bash
make anvil
```

## Deploy

This will default to your local node. Ensure you have it running in another terminal for deployment.

```bash
make deploy
```

## Deploy - Other Network

[See below](#deployment-to-a-testnet-or-mainnet)

## Testing

We cover the following four test tiers in this project:

1. Unit
2. Integration
3. Forked
4. Staging

In this repo, we focus on #1 and Fuzzing.

```bash
forge test
```

### Test Coverage

```bash
forge coverage
```

For coverage-based testing:

```bash
forge coverage --report debug
```

# Deployment to a testnet or mainnet

1. **Setup environment variables**

   You'll want to set your `SEPOLIA_RPC_URL` and `PRIVATE_KEY` as environment variables. You can add them to a `.env` file, similar to what you see in `.env.example`.

   - `PRIVATE_KEY`: The private key of your account (like from [metamask](https://metamask.io/)). **NOTE:** FOR DEVELOPMENT, USE A KEY THAT DOES NOT HAVE ANY REAL FUNDS ASSOCIATED WITH IT.
     - You can [learn how to export it here](https://metamask.zendesk.com/hc/en-us/articles/360015289632-How-to-Export-an-Account-Private-Key).
   - `SEPOLIA_RPC_URL`: This is the URL of the Sepolia testnet node you're working with. You can get set up with one for free from [Alchemy](https://alchemy.com/?a=673c802981).

   Optionally, add your `ETHERSCAN_API_KEY` if you want to verify your contract on [Etherscan](https://etherscan.io/).

2. **Get testnet ETH**

   Head over to [faucets.chain.link](https://faucets.chain.link/) and get some testnet ETH. You should see the ETH show up in your MetaMask.

3. **Deploy**

   ```bash
   make deploy ARGS="--network sepolia"
   ```

## Scripts

Instead of scripts, we can directly use the `cast` command to interact with the contract. Here are some examples for Sepolia:

1. **Get some WETH**

   ```bash
   cast send 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 "deposit()" --value 0.1ether --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
   ```

2. **Approve the WETH**

   ```bash
   cast send 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 "approve(address,uint256)" 0x091EA0838eBD5b7ddA2F2A641B068d6D59639b98 1000000000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
   ```

3. **Deposit and Mint DSC**

   ```bash
   cast send 0x091EA0838eBD5b7ddA2F2A641B068d6D59639b98 "depositCollateralAndMintDsc(address,uint256,uint256)" 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 100000000000000000 10000000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
   ```

## Estimate Gas

You can estimate how much gas transactions will cost by running:

```bash
forge snapshot
```

This will generate an output file called `.gas-snapshot`.

# Formatting

To run code formatting, use:

```bash
forge fmt
```

# Slither

To analyze the code for potential vulnerabilities, run:

```bash
slither . --config-file slither.config.json
```

# Additional Info

Some users have expressed confusion about whether Chainlink-brownie-contracts is an official Chainlink repository. Here’s the information:

Chainlink-brownie-contracts is indeed an official repository. It is owned and maintained by the Chainlink team, following the proper Chainlink release process. You can see it still resides under the `smartcontractkit` organization.

[Chainlink Brownie Contracts GitHub](https://github.com/smartcontractkit/chainlink-brownie-contracts)

## Let's Talk About What "Official" Means

The "official" release process indicates that Chainlink deploys its packages to [npm](https://www.npmjs.com/package/@chainlink/contracts). Therefore, downloading directly from `smartcontractkit/chainlink` could potentially use unreleased code.

You have two options:

1. Download from NPM and introduce dependencies that are not compatible with Foundry.
2. Download from the Chainlink-brownie-contracts repo, which packages the NPM releases appropriately for use with Foundry.

## Summary

1. This is an official repository maintained by the same organization.
2. It pulls from the official release cycle (`chainlink/contracts` on npm) and packages it for easy use with Foundry.


