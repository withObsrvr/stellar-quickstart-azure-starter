#!/usr/bin/env python3
"""Create and fund test accounts on the Stellar sandbox via Friendbot.

Generates fresh keypairs, funds each with 10,000 XLM, verifies the balance
through Horizon, and writes them to a JSON file for tests to load.

The local network is ephemeral: accounts vanish when the container restarts,
so re-run this after every deploy/restart. Two reachability modes:

  Direct (endpoint reachable from this machine — public mode, VPN, or in-VNet):
    ./seed_accounts.py --endpoint http://quickstart.stellar.internal:8000

  Exec (private mode, no network path — e.g. from an Azure DevOps hosted
  agent; goes through the Azure control plane via `az container exec`):
    ./seed_accounts.py --via-exec <resource-group> <container-group>

With neither flag, the endpoint is read from `terraform output`.
"""
import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

try:
    from stellar_sdk import Keypair
except ImportError:
    sys.exit("stellar-sdk is required: pip install -r scripts/requirements.txt")


def http_get_json(url, timeout=30):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return json.load(r)


class DirectTransport:
    def __init__(self, endpoint):
        self.endpoint = endpoint.rstrip("/")

    def get(self, path):
        return http_get_json(f"{self.endpoint}{path}")


class ExecTransport:
    """Reach the quickstart via `az container exec` — control plane only,
    works when there is no network path to the private endpoint."""

    def __init__(self, resource_group, container_group):
        self.rg = resource_group
        self.cg = container_group

    def get(self, path):
        cmd = [
            "az", "container", "exec",
            "-g", self.rg, "-n", self.cg,
            "--container-name", "quickstart",
            "--exec-command", f"curl -s --max-time 30 http://localhost:8000{path}",
        ]
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=90).stdout
        # exec output can carry terminal control characters; find the JSON body.
        start = out.find("{")
        if start == -1:
            raise RuntimeError(f"no JSON in exec output: {out[:200]!r}")
        return json.loads(out[start:out.rfind("}") + 1])


def terraform_endpoint():
    try:
        out = subprocess.run(
            ["terraform", "output", "-raw", "stellar_endpoint"],
            capture_output=True, text=True, check=True, timeout=60,
        ).stdout.strip()
        if out.startswith("http"):
            return out
    except (subprocess.SubprocessError, FileNotFoundError):
        pass
    sys.exit("Could not read stellar_endpoint from terraform output; pass --endpoint or --via-exec")


def fund(transport, name, keypair, retries=5):
    addr = keypair.public_key
    for attempt in range(1, retries + 1):
        try:
            result = transport.get(f"/friendbot?addr={addr}")
            if result.get("successful"):
                return
            detail = result.get("detail") or result.get("title") or str(result)[:200]
            raise RuntimeError(detail)
        except (urllib.error.URLError, RuntimeError, json.JSONDecodeError) as e:
            if attempt == retries:
                raise RuntimeError(f"{name}: funding failed after {retries} tries: {e}")
            time.sleep(3)


def verify(transport, keypair, retries=10):
    for attempt in range(1, retries + 1):
        try:
            acct = transport.get(f"/accounts/{keypair.public_key}")
            for b in acct.get("balances", []):
                if b.get("asset_type") == "native":
                    return b["balance"]
        except (urllib.error.URLError, RuntimeError, json.JSONDecodeError):
            pass
        if attempt < retries:
            time.sleep(3)
    return None


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--count", type=int, default=5, help="number of accounts (default 5)")
    p.add_argument("--endpoint", help="quickstart endpoint, e.g. http://host:8000")
    p.add_argument("--via-exec", nargs=2, metavar=("RESOURCE_GROUP", "CONTAINER_GROUP"),
                   help="fund through `az container exec` instead of direct HTTP")
    p.add_argument("--output", default="seed-accounts.json", help="output file (default seed-accounts.json)")
    args = p.parse_args()

    if args.via_exec:
        transport = ExecTransport(*args.via_exec)
        print(f"Funding via az container exec ({args.via_exec[0]}/{args.via_exec[1]})")
    else:
        endpoint = args.endpoint or terraform_endpoint()
        transport = DirectTransport(endpoint)
        print(f"Funding via {endpoint}")

    accounts = []
    for i in range(1, args.count + 1):
        name = f"account-{i}"
        kp = Keypair.random()
        fund(transport, name, kp)
        balance = verify(transport, kp)
        if balance is None:
            sys.exit(f"{name}: funded but never appeared in Horizon — is the network healthy?")
        accounts.append({"name": name, "public_key": kp.public_key, "secret_key": kp.secret})
        print(f"  {name}: {kp.public_key} balance={balance}")

    with open(args.output, "w") as f:
        json.dump({"accounts": accounts}, f, indent=2)
    print(f"\nWrote {len(accounts)} accounts to {args.output}")
    print("Contains SECRET KEYS — keep it out of git (already in .gitignore).")


if __name__ == "__main__":
    main()
