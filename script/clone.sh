#!/usr/bin/env bash
# crucible/script/clone.sh — predict the address of an EIP-1167 clone produced
# by a Bitsy deployer's `make()` call, and write io/<CloneName>/<addr>.{txt,yml}.
#
# Sourcing this file cd's to the repo root so relative io/<contract>/... paths
# resolve consistently regardless of where the calling script was invoked from.
#
# Usage:
#   source "$(git rev-parse --show-toplevel)/lib/crucible/script/clone.sh"
#   clone_predict <CloneName> <deployer> <argsType> <argsValue>... <variant>
#
# Optional env vars (captured into the yml when set):
#   mask, target — vanity-mining inputs from saltminer

cd "$(git rev-parse --show-toplevel)"

# clone_predict — predict the address of a Bitsy clone deployed by <deployer>'s
# `make(<argsType>, uint256 variant)` call, and write the .txt and .yml
# artifacts. No .json is written (clones use proxy verification).
#
# Args:
#   CloneName  — directory name under io/ for the artifacts
#   deployer    — the Bitsy prototype that deploys this clone
#   argsType   — comma-separated Solidity types of make()'s args before
#                variant — what would go between the parens in a function
#                signature. One arg: "(uint256,address)[]" (AddressLookup),
#                multi-arg: "address,string" (Reflector).
#   argsValue… — one CLI value per top-level type in argsType.
#                AddressLookup: a single array literal "[(1,0xabc),(8453,0xdef)]".
#                Reflector:     two values, "$peg" "$symbol".
#   variant    — uint256 hex value mined for the desired vanity address
#
# Stdout: prints "<CloneName>=<addr>".
clone_predict() {
    local clone="$1"
    local deployer="$2"
    local argstype="$3"
    shift 3
    local variant="${!#}"
    local args_values=("${@:1:$#-1}")

    # EIP-1167 minimal proxy initcode keyed to the deployer.
    local proxy_initcode="0x3d602d80600a3d3981f3363d3d373d3d3d363d73${deployer#0x}5af43d82803e903d91602b57fd5bf3"
    local initcodehash
    initcodehash=$(cast keccak "$proxy_initcode")

    # Prototype.made(bytes args, uint256 variant) computes
    #   argshash = keccak256(args)
    #   salt     = argshash ^ variant
    # where args is the `bytes` parameter's content — exactly what
    # cast abi-encode "f(<argstype>)" already produces.
    local args_bytes
    args_bytes=$(cast abi-encode "f($argstype)" "${args_values[@]}")
    local argshash
    argshash=$(cast keccak "$args_bytes")

    # XOR is too wide for bash arithmetic; defer to python.
    local salt
    salt=$(python3 -c "print(f'0x{int(\"$argshash\",16) ^ int(\"$variant\",16):064x}')")

    local addr
    addr=$(cast create2 --deployer "$deployer" --salt "$salt" --init-code "$proxy_initcode")

    local dir="io/$clone"
    mkdir -p "$dir"

    # The .txt file is the calldata sent to the deployer:
    # Prototype.make(bytes args, uint256 variant).
    local input
    input=$(cast calldata "make(bytes,uint256)" "$args_bytes" "$variant")
    printf '%s' "$input" > "$dir/$addr.txt"

    {
        echo "contract: $clone"
        echo "kind: clone"
        echo "deployer: \"$deployer\""
        echo "initcodehash: \"$initcodehash\""
        echo "argstype: \"$argstype\""
        echo "argshash: \"$argshash\""
        if [[ -n "${mask:-}" ]]; then
            echo "mask: \"$mask\""
        fi
        if [[ -n "${target:-}" ]]; then
            echo "target: \"$target\""
        fi
        echo "variant: \"$variant\""
        echo "home: \"$addr\""
    } > "$dir/$addr.yml"

    echo "$clone=$addr"
}
