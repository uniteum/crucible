#!/usr/bin/env bash
# crucible/script/lib.sh — deployment helpers sourced by per-contract scripts.
#
# Sourcing this file cd's to the repo root so relative io/<contract>/... paths
# resolve consistently regardless of where the calling script was invoked from.
#
# Usage:
#   source "$(git rev-parse --show-toplevel)/lib/crucible/script/lib.sh"
#   proto_predict <ContractName> <salt> [<constructorSig> <arg>...]

cd "$(git rev-parse --show-toplevel)"

NICK=0x4e59b44847b379578588920cA78FbF26c0B4956C

# proto_predict <ContractName> <salt> [<constructorSig> <arg>...]
#
# Predicts the CREATE2 address of a Nick-deployed prototype and writes
# io/<ContractName>/<addr>.{txt,yml,json}.
#
# Args:
#   ContractName    — name resolvable by `forge inspect`
#   salt            — 32-byte hex CREATE2 salt
#   constructorSig  — optional Solidity-style signature (e.g. "constructor(address)")
#   <arg>...        — constructor arg values
#
# Stdout: prints "<ContractName>=<addr>".
proto_predict() {
    local contract="$1"
    local salt="$2"
    shift 2

    local bytecode initcode
    bytecode=$(forge inspect "$contract" bytecode)
    if [[ $# -gt 0 ]]; then
        local sig="$1"
        shift
        local args
        args=$(cast abi-encode "$sig" "$@")
        initcode=$(cast concat-hex "$bytecode" "$args")
    else
        initcode="$bytecode"
    fi

    local addr
    addr=$(cast create2 --deployer "$NICK" --salt "$salt" --init-code "$initcode")

    local dir="io/$contract"
    mkdir -p "$dir"

    local input
    input=$(cast concat-hex "$salt" "$initcode")
    printf '%s' "$input" > "$dir/$addr.txt"

    {
        echo "contract: $contract"
        echo "kind: prototype"
        echo "deployer: \"$NICK\""
        echo "initcodeHash: \"$(cast keccak "$initcode")\""
        echo "salt: \"$salt\""
        if [[ -n "${mask:-}" ]]; then
            echo "mask: \"$mask\""
        fi
        if [[ -n "${target:-}" ]]; then
            echo "target: \"$target\""
        fi
    } > "$dir/$addr.yml"

    forge verify-contract "$addr" "$contract" \
        --verifier etherscan --show-standard-json-input \
        | jq '.' > "$dir/$addr.json"

    echo "$contract=$addr"
}
