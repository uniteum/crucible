#!/usr/bin/env bash
# crucible/script/deploy.sh — deploy a single committed io/<contract>/<addr>.yml
# entry on a given chain, recursively ensuring its deployer chain first.
#
# Usage (from a consumer repo's root):
#   tx_key=0x... bash lib/crucible/script/deploy.sh <chain> <addr>
#
# <chain> is a key in foundry.toml's [rpc_endpoints] or an RPC URL.
# <addr> is the target contract address; its yml must exist somewhere
# under io/<contract>/<addr>.yml in this repo. The yml's `deployer` is
# itself looked up and (if needed) deployed first, recursively.
#
# tx_key is only required if at least one tx must be broadcast; if every
# address in the dependency chain already has code on <chain>, the script
# is a read-only check.
#
# Cross-repo deps: by default, deploy.sh also walks io/ in every sibling
# directory of this repo (../*/io). Override the search root by setting
# io_root=/path/to/parent. This avoids importing other repos as submodules
# just to read their deployment artifacts.

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <chain> <addr>" >&2
    exit 2
fi

chain="$1"
target=$(cast --to-checksum-address "$2")
: "${tx_key:=}"

# Build addr → yml-path map by walking io/*/<addr>.yml in this repo and
# in every sibling repo's io/. The yml's `deployer` field identifies what
# each address is, so collecting them all in a flat map is safe.
: "${io_root:=..}"
declare -A YML_PATH
for io_dir in io "$io_root"/*/io; do
    [[ -d "$io_dir" ]] || continue
    while IFS= read -r yml; do
        addr=$(basename "$yml" .yml)
        YML_PATH[$addr]="$yml"
    done < <(find "$io_dir" -mindepth 2 -maxdepth 2 -type f -name '0x*.yml' 2>/dev/null)
done

if [[ ${#YML_PATH[@]} -eq 0 ]]; then
    echo "No io/*/<addr>.yml entries found in this repo or under $io_root" >&2
    exit 1
fi

# Read a value out of a yml file, stripping surrounding double quotes.
yml_field() {
    local raw
    raw=$(awk -v key="$2:" '$1==key {print $2; exit}' "$1")
    raw=${raw#\"}; raw=${raw%\"}
    echo "$raw"
}

# Recursive: ensure addr has code on $chain, deploying it via its deployer if not.
deploy() {
    local addr="$1"
    local code
    code=$(cast code "$addr" --rpc-url "$chain")
    if [[ "$code" != "0x" ]]; then
        return
    fi

    local yml="${YML_PATH[$addr]:-}"
    if [[ -z "$yml" ]]; then
        echo "ERROR: $addr has no code on $chain and no io/*/<addr>.yml entry" >&2
        echo "       (if its yml lives in another repo, deploy from there first)" >&2
        return 1
    fi

    local deployer
    deployer=$(cast --to-checksum-address "$(yml_field "$yml" deployer)")

    deploy "$deployer"

    if [[ -z "$tx_key" ]]; then
        echo "ERROR: tx_key not set; cannot broadcast $addr via $deployer" >&2
        return 1
    fi

    local contract input
    contract=$(yml_field "$yml" contract)
    input=$(cat "${yml%.yml}.txt")
    echo "Deploying $contract → $addr via $deployer on $chain..."
    cast send "$deployer" "$input" --rpc-url "$chain" --private-key "$tx_key"
}

deploy "$target"
echo "$target is deployed on $chain."
