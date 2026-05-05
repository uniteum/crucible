#!/usr/bin/env bash
# crucible/script/deploy.sh — broadcast committed io/<contract>/<addr>.txt
# files to their declared deployers, recursively ensuring prerequisites.
#
# Usage (from a consumer repo's root):
#   tx_key=0x... bash lib/crucible/script/deploy.sh <chain>
#
# <chain> is a key in foundry.toml's [rpc_endpoints] or an RPC URL.
# tx_key is only required if at least one address still needs broadcasting;
# if the entire graph is already deployed, the script is a read-only check.

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <chain>" >&2
    exit 2
fi

chain="$1"
: "${tx_key:=}"

declare -A YML_PATH
while IFS= read -r yml; do
    addr=$(basename "$yml" .yml)
    YML_PATH[$addr]="$yml"
done < <(find io -mindepth 2 -maxdepth 2 -type f -name '0x*.yml' 2>/dev/null)

if [[ ${#YML_PATH[@]} -eq 0 ]]; then
    echo "No io/*/<addr>.yml entries found under $(pwd)" >&2
    exit 1
fi

yml_field() {
    local raw
    raw=$(awk -v key="$2:" '$1==key {print $2; exit}' "$1")
    raw=${raw#\"}; raw=${raw%\"}
    echo "$raw"
}

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
        return 1
    fi

    local deployer
    deployer=$(yml_field "$yml" deployer)

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

for addr in "${!YML_PATH[@]}"; do
    deploy "$addr"
done

echo "All io/*/<addr>.yml entries are deployed on $chain."
