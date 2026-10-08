# Connecting your application

The sandbox behaves like the real Stellar network. Switching an app between
this sandbox, testnet, and pubnet is a configuration change — **three values**,
no code changes:

| Value | Sandbox (`stellar_network = "local"`) | Testnet | Pubnet |
|---|---|---|---|
| Horizon URL | `http://<endpoint>:8000` | `https://horizon-testnet.stellar.org` | `https://horizon.stellar.org` |
| RPC URL | `http://<endpoint>:8000/rpc` | `https://soroban-testnet.stellar.org` | (run your own) |
| Network passphrase | `Standalone Network ; February 2017` | `Test SDF Network ; September 2015` | `Public Global Stellar Network ; September 2015` |

`<endpoint>` is the complete URL returned by `terraform output -raw
stellar_endpoint`, including the `http://` scheme and port `8000`. Friendbot
(the faucet) is at `<endpoint>/friendbot` on the sandbox — see the
[module's Friendbot guide] for funding accounts, and `scripts/seed_accounts.py`
for pre-funded test accounts.

The sandbox is plain HTTP on a private network, so SDKs need their
"allow http" option (shown below). One more sandbox-ism to design tests
around: the local network is **ephemeral** — a container restart resets it to
genesis, so tests should create (or re-seed) their fixtures rather than assume
accounts persist.

[module's Friendbot guide]: https://github.com/withobsrvr/terraform-azure-stellar-quickstart/blob/main/docs/FRIENDBOT.md

## JavaScript / TypeScript (`@stellar/stellar-sdk`)

```js
import { Horizon, rpc, Networks } from "@stellar/stellar-sdk";

const SANDBOX = "http://quickstart.stellar.internal:8000";
const NETWORK_PASSPHRASE = "Standalone Network ; February 2017"; // Networks.STANDALONE

const horizon = new Horizon.Server(SANDBOX, { allowHttp: true });
const rpcServer = new rpc.Server(`${SANDBOX}/rpc`, { allowHttp: true });

// Everything else is identical to mainnet/testnet code — pass
// NETWORK_PASSPHRASE wherever you build/sign transactions.
```

## Python (`stellar-sdk`)

```python
from stellar_sdk import Server, SorobanServer, TransactionBuilder

SANDBOX = "http://quickstart.stellar.internal:8000"
NETWORK_PASSPHRASE = "Standalone Network ; February 2017"

horizon = Server(SANDBOX)
soroban = SorobanServer(f"{SANDBOX}/rpc")

# tx = TransactionBuilder(source_account, network_passphrase=NETWORK_PASSPHRASE, ...)
```

## stellar-cli

```bash
stellar network add sandbox \
  --rpc-url "http://quickstart.stellar.internal:8000/rpc" \
  --network-passphrase "Standalone Network ; February 2017"

stellar contract deploy --network sandbox ...
```

## Loading seeded accounts in tests

`scripts/seed_accounts.py` writes `seed-accounts.json` (gitignored — it
contains secret keys):

```json
{
  "accounts": [
    { "name": "account-1", "public_key": "G...", "secret_key": "S..." }
  ]
}
```

```js
import { readFileSync } from "fs";
import { Keypair } from "@stellar/stellar-sdk";

const seed = JSON.parse(readFileSync("seed-accounts.json", "utf8"));
const alice = Keypair.fromSecret(seed.accounts[0].secret_key);
```

In CI, the pipeline publishes the file as the `seed-accounts` artifact after
each apply.

## Reaching a private sandbox

In `network_access = "private"` mode (the default), these URLs only resolve
and route from inside the VNet, a peered VNet, or over the optional VPN. See
the [module README](https://github.com/withobsrvr/terraform-azure-stellar-quickstart#readme)
for the access options. Apps deployed in Azure should run in (or peer with)
the sandbox VNet; developer laptops need the VPN.
