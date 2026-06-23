#!/usr/bin/env bash
# crucible/script/deploy.sh — deploy a single committed io/<contract>/<addr>.yml
# entry on a given chain, recursively ensuring its deployer chain first.
#
# Usage (from a consumer repo's root):
#   bash lib/crucible/script/deploy.sh [-b|--broadcast] [<wallet-flags>] <chain> <addr>
#
# Default is dry-run: walks the dep chain and prints what would be
# deployed in order, without sending any transactions. Pass -b or
# --broadcast to actually send.
#
# Wallet selection (for broadcast mode):
#   - default: --private-key "$tx_key" (raw key from env)
#   - override: pass any cast wallet flag(s) before the positional args.
#     e.g. --account dev    (foundry keystore alias)
#          --keystore <path>
#          --ledger / --trezor / --frame
#          --mnemonic "<phrase>" --mnemonic-index 3
#   When any wallet flag is passed, $tx_key is ignored.
#
# <chain> is a key in foundry.toml's [rpc_endpoints] or an RPC URL.
# <addr> is the target contract address; its yml must exist somewhere
# under io/<contract>/<addr>.yml in this repo. The yml's `deployer` is
# itself looked up and (if needed) deployed first, recursively.
#
# Cross-repo deps: by default, deploy.sh also walks io/ in every sibling
# directory of this repo (../*/io). Override the search root by setting
# io_root=/path/to/parent. This avoids importing other repos as submodules
# just to read their deployment artifacts.

set -euo pipefail

# Parse flags. Default is dry-run; -b/--broadcast actually sends txs.
# Any other flag is treated as a cast wallet flag and forwarded to cast send.
broadcast=0
wallet_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--broadcast) broadcast=1; shift ;;
        --) shift; break ;;
        -*)
            # Pass-through: assume "--flag value" unless next arg is another flag
            # or there is no next arg (e.g. --ledger is a no-arg flag).
            if [[ $# -gt 1 && "$2" != -* ]]; then
                wallet_args+=("$1" "$2"); shift 2
            else
                wallet_args+=("$1"); shift
            fi
            ;;
        *) break ;;
    esac
done

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 [-b|--broadcast] [<wallet-flags>] <chain> <addr>" >&2
    exit 2
fi

chain="$1"
target=$(cast --to-checksum-address "$2")
: "${tx_key:=}"

# In broadcast mode, fall back to tx_key if no wallet flags were given.
if [[ "$broadcast" -eq 1 && ${#wallet_args[@]} -eq 0 ]]; then
    if [[ -z "$tx_key" ]]; then
        echo "ERROR: no wallet specified; set tx_key or pass --account/--private-key/--ledger/etc." >&2
        exit 1
    fi
    wallet_args=(--private-key "$tx_key")
fi

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

# Memoize addresses we've already visited so the same contract isn't
# re-checked or re-printed during a single run (especially in dry-run,
# where cast code keeps reporting empty since nothing is broadcast).
declare -A VISITED

# Recursive: ensure addr has code on $chain. Walks both:
#   - the deployer chain (who creates this contract)
#   - any constructor-arg addresses (runtime references the contract
#     will need to function), if they have ymls of their own
#
# Constructor args without a yml entry (external addresses like Uniswap
# V4 PoolManagers, USDC, etc.) are silently skipped.
deploy() {
    local addr="$1"
    [[ -n "${VISITED[$addr]:-}" ]] && return
    VISITED[$addr]=1

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

    # Walk constructor-arg addresses captured under `args:` in the yml.
    # Each entry is tested for being a valid address; if so and we have
    # a yml for it, recurse so its dep chain is also satisfied.
    if yq -e .args "$yml" >/dev/null 2>&1; then
        while IFS= read -r arg; do
            [[ -z "$arg" || "$arg" == "null" ]] && continue
            local arg_addr
            arg_addr=$(cast --to-checksum-address "$arg" 2>/dev/null) || continue
            if [[ -n "${YML_PATH[$arg_addr]:-}" ]]; then
                deploy "$arg_addr"
            fi
        done < <(yq -r '.args[]' "$yml" 2>/dev/null)
    fi

    local contract input
    contract=$(yml_field "$yml" contract)
    input=$(cat "${yml%.yml}.txt")

    if [[ "$broadcast" -eq 0 ]]; then
        echo "[dry-run] would deploy $contract → $addr via $deployer on $chain"
        return
    fi

    echo "Deploying $contract → $addr via $deployer on $chain..."
    cast send "$deployer" "$input" --rpc-url "$chain" "${wallet_args[@]}"
}

deploy "$target"

if [[ "$broadcast" -eq 0 ]]; then
    echo "[dry-run] done. Pass -b/--broadcast to actually send transactions."
else
    echo "$target is deployed on $chain."
fi
