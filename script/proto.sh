#!/usr/bin/env bash
# crucible/script/proto.sh — predict a Nick-deployed prototype's CREATE2
# address and write io/<Contract>/<addr>.{txt,yml,json}.
#
# Sourcing this file cd's to the repo root so relative io/<contract>/... paths
# resolve consistently regardless of where the calling script was invoked from.
#
# Usage:
#   source "$(git rev-parse --show-toplevel)/lib/crucible/script/proto.sh"
#   proto_predict <ContractName> <salt> [<constructorSig> <arg>...]

# Shared CREATE2-input formulas (saltminer_url, etc.), sourced by absolute path
# so it resolves regardless of the caller's cwd.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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
    local -a constructor_args=()
    bytecode=$(forge inspect "$contract" bytecode)
    if [[ $# -gt 0 ]]; then
        local sig="$1"
        shift
        constructor_args=("$@")
        local encoded
        encoded=$(cast abi-encode "$sig" "${constructor_args[@]}")
        initcode=$(cast concat-hex "$bytecode" "$encoded")
    else
        initcode="$bytecode"
    fi

    local initcodehash
    initcodehash=$(cast keccak "$initcode")

    local addr
    addr=$(cast create2 --deployer "$NICK" --salt "$salt" --init-code "$initcode")

    local dir="io/$contract"
    mkdir -p "$dir"

    local input
    input=$(cast concat-hex "$salt" "$initcode")
    printf '%s' "$input" > "$dir/$addr.txt"

    # Capture the compiler version that produced this initcode so verify.sh
    # can submit it to Etherscan even if foundry.toml later changes solc.
    local compilerversion
    compilerversion="v$(forge inspect "$contract" metadata | jq -r .compiler.version)"

    # Capture the SPDX license identifier from the source file's first line.
    # Same reasoning: insulate verify.sh from later edits to the source.
    local license
    license=$(grep -m1 "SPDX-License-Identifier:" "src/$contract.sol" \
              | sed 's|.*SPDX-License-Identifier: *||' \
              | tr -d '\r')
    : "${license:=None}"

    {
        echo "contract: $contract"
        echo "kind: prototype"
        echo "deployer: \"$NICK\""
        echo "initcodehash: \"$initcodehash\""
        echo "salt: \"$salt\""
        echo "compilerversion: \"$compilerversion\""
        echo "license: \"$license\""
        if [[ -n "${mask:-}" ]]; then
            echo "mask: \"$mask\""
        fi
        if [[ -n "${target:-}" ]]; then
            echo "target: \"$target\""
        fi
        # A prototype folds nothing into the salt field, so its saltminer
        # argshash is 32 zero bytes and the mined salt is the CREATE2 salt.
        if [[ -n "${mask:-}" && -n "${target:-}" ]]; then
            echo "saltminer: \"$(saltminer_url "$NICK" "$initcodehash" \
                0x0000000000000000000000000000000000000000000000000000000000000000 \
                "$mask" "$target")\""
        fi
        if [[ ${#constructor_args[@]} -gt 0 ]]; then
            echo "args:"
            for arg in "${constructor_args[@]}"; do
                echo "  - \"$arg\""
            done
        fi
        echo "home: \"$addr\""
    } > "$dir/$addr.yml"

    forge verify-contract "$addr" "$contract" \
        --verifier etherscan --show-standard-json-input \
        | jq '.' > "$dir/$addr.json"

    echo "$contract=$addr"
}
