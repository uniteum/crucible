#!/usr/bin/env bash
# verify.sh — verify a deployed contract on Etherscan by submitting the
# standard-input JSON we captured at predict time.
#
# Usage:
#   ETHERSCAN_API_KEY=... bash lib/crucible/script/verify.sh <chain> <addr>
#
# This intentionally does NOT use `forge verify-contract`. Forge would
# regenerate the standard input from the current source + foundry.toml,
# which can drift away from what was actually deployed (different solc
# version, modified source, etc.). We ship the .json that was committed
# alongside the .txt — the same bytes that produced the on-chain code.
#
# For prototypes with constructor args, set $constructor_args to the
# abi-encoded value (with or without 0x prefix).
#
# Clones (kind: clone) are not verified here — Etherscan auto-detects
# EIP-1167 proxies and inherits the deployer prototype's verified source.

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <chain> <addr>" >&2
    exit 2
fi

chain="$1"
target=$(cast --to-checksum-address "$2")
: "${ETHERSCAN_API_KEY:?set ETHERSCAN_API_KEY}"
: "${io_root:=..}"
: "${constructor_args:=}"

# Find the yml for this address. Looks in local io/ first, then sibling
# repos under $io_root. nullglob makes a non-matching glob expand to
# nothing instead of leaving the literal pattern in the array.
shopt -s nullglob
matches=(io/*/"$target".yml "$io_root"/*/io/*/"$target".yml)
shopt -u nullglob

if [[ ${#matches[@]} -eq 0 ]]; then
    echo "ERROR: no io/*/$target.yml found" >&2
    exit 1
fi
yml="${matches[0]}"
json="${yml%.yml}.json"

contract=$(yq -r .contract "$yml")
kind=$(yq -r .kind "$yml")

if [[ "$kind" == "clone" ]]; then
    deployer=$(yq -r .deployer "$yml")
    echo "$contract → $target is an EIP-1167 clone of $deployer."
    echo "Etherscan auto-detects the proxy. Verify the deployer instead:"
    echo "    bash lib/crucible/script/verify.sh $chain $deployer"
    exit 0
fi

compilerversion=$(yq -r .compilerversion "$yml")
if [[ -z "$compilerversion" || "$compilerversion" == "null" ]]; then
    echo "ERROR: compilerversion missing from $yml" >&2
    echo "       Re-run the predict script to regenerate the yml." >&2
    exit 1
fi

if [[ ! -f "$json" ]]; then
    echo "ERROR: no standard-input JSON at $json" >&2
    exit 1
fi

# Etherscan wants raw hex, no leading 0x.
constructor_args=${constructor_args#0x}

echo "Submitting $contract → $target on chain $chain (compiler $compilerversion)..."
response=$(curl -sS -X POST "https://api.etherscan.io/v2/api?chainid=$chain" \
    --data-urlencode "module=contract" \
    --data-urlencode "action=verifysourcecode" \
    --data-urlencode "apikey=$ETHERSCAN_API_KEY" \
    --data-urlencode "contractaddress=$target" \
    --data-urlencode "contractname=src/$contract.sol:$contract" \
    --data-urlencode "compilerversion=$compilerversion" \
    --data-urlencode "codeformat=solidity-standard-json-input" \
    --data-urlencode "constructorArguements=$constructor_args" \
    --data-urlencode "sourceCode@$json")

status=$(echo "$response" | jq -r .status)
guid=$(echo "$response" | jq -r .result)
if [[ "$status" != "1" ]]; then
    echo "ERROR: $response" >&2
    exit 1
fi

echo "Submitted (GUID $guid). Polling..."
for i in {1..30}; do
    sleep 3
    check=$(curl -sS "https://api.etherscan.io/v2/api?chainid=$chain&module=contract&action=checkverifystatus&guid=$guid&apikey=$ETHERSCAN_API_KEY")
    msg=$(echo "$check" | jq -r .result)
    case "$msg" in
        Pending*) echo "  [$i] $msg" ;;
        Pass*|*successfully*) echo "  ✓ $msg"; exit 0 ;;
        *) echo "  ✗ $msg" >&2; exit 1 ;;
    esac
done
echo "ERROR: timeout waiting for verification" >&2
exit 1
