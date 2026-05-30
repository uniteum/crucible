#!/usr/bin/env bash
# crucible/script/clone.sh — predict the address of an EIP-1167 clone produced
# by a Bitsy deployer's `make()` call, and write io/<CloneName>/<addr>.{txt,yml}.
#
# Sourcing this file cd's to the repo root so relative io/<contract>/... paths
# resolve consistently regardless of where the calling script was invoked from.
#
# Usage:
#   source "$(git rev-parse --show-toplevel)/lib/crucible/script/clone.sh"
#   clone_predict <CloneName> <deployer> <argsType> <argsValue>... <variant> \
#       [-- <target> <callSig> <callArg>...]
#
# Optional env vars (captured into the yml when set):
#   mask, target — vanity-mining inputs from saltminer

# Shared CREATE2-input formulas (also used by the mining step). Sourced
# by absolute path so it resolves regardless of the caller's cwd.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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
# Optional call spec (after a `--` separator): <target> <callSig> <callArg>...
#   By default the .txt holds the generic `deployer.make(bytes args, uint256
#   variant)` calldata. A two-level factory instead mints its clone through a
#   purpose-built function on a different contract — e.g. a Reflector issue is
#   created by `maker.issue(name, variant, supply)`, not by calling the
#   coinage's make(bytes,uint256). Pass that call here and clone_predict
#   encodes it into the .txt and records <target> as the yml `via:` so
#   deploy.sh broadcasts to it instead of to <deployer>.
#     target   — the contract the transaction is sent to (the yml `via:`)
#     callSig  — the function signature to encode (e.g. "issue(string,uint256,uint256)")
#     callArg… — one value per parameter in callSig
#
# Stdout: prints "<CloneName>=<addr>".
clone_predict() {
    local clone="$1"
    local deployer="$2"
    local argstype="$3"
    shift 3

    # Split the rest on an optional `--`: the address-determining args (whose
    # keccak is the argshash) and the variant come first; an explicit on-chain
    # call to encode into the .txt comes after.
    local -a pre=() call=()
    local in_call=0 a
    for a in "$@"; do
        if [[ $in_call -eq 0 && "$a" == "--" ]]; then in_call=1; continue; fi
        if [[ $in_call -eq 0 ]]; then pre+=("$a"); else call+=("$a"); fi
    done

    local variant="${pre[-1]}"
    local args_values=("${pre[@]:0:${#pre[@]}-1}")

    # EIP-1167 minimal proxy initcode keyed to the deployer.
    local proxy_initcode
    proxy_initcode=$(clone_proxy_initcode "$deployer")
    local initcodehash
    initcodehash=$(cast keccak "$proxy_initcode")

    # Prototype.made(bytes args, uint256 variant) computes
    #   argshash = keccak256(args)
    #   salt     = argshash ^ variant
    # where args is the `bytes` parameter's content — exactly what
    # cast abi-encode "f(<argstype>)" already produces.
    local args_bytes
    args_bytes=$(clone_args_bytes "$argstype" "${args_values[@]}")
    local argshash
    argshash=$(cast keccak "$args_bytes")

    # XOR is too wide for bash arithmetic; defer to python.
    local salt
    salt=$(python3 -c "print(f'0x{int(\"$argshash\",16) ^ int(\"$variant\",16):064x}')")

    local addr
    addr=$(cast create2 --deployer "$deployer" --salt "$salt" --init-code "$proxy_initcode")

    local dir="io/$clone"
    mkdir -p "$dir"

    # The .txt file is the calldata an operator broadcasts to create this
    # clone, and `via` is the contract it is sent to. By default that is the
    # generic deployer.make(bytes args, uint256 variant); an explicit call spec
    # overrides both (e.g. maker.issue(name, variant, supply)).
    local input via
    if [[ ${#call[@]} -gt 0 ]]; then
        via="${call[0]}"
        input=$(cast calldata "${call[1]}" "${call[@]:2}")
    else
        via="$deployer"
        input=$(cast calldata "make(bytes,uint256)" "$args_bytes" "$variant")
    fi
    printf '%s' "$input" > "$dir/$addr.txt"

    {
        echo "contract: $clone"
        echo "kind: clone"
        echo "deployer: \"$deployer\""
        # The CREATE2 deployer fixes the address; `via` is who the creation tx
        # is sent to. They differ only for two-level factories (e.g. issues),
        # so it is omitted when they coincide.
        if [[ "$via" != "$deployer" ]]; then
            echo "via: \"$via\""
        fi
        echo "initcodehash: \"$initcodehash\""
        echo "argstype: \"$argstype\""
        echo "argshash: \"$argshash\""
        if [[ -n "${mask:-}" ]]; then
            echo "mask: \"$mask\""
        fi
        if [[ -n "${target:-}" ]]; then
            echo "target: \"$target\""
        fi
        if [[ -n "${mask:-}" && -n "${target:-}" ]]; then
            echo "saltminer: \"$(saltminer_url "$deployer" "$initcodehash" "$argshash" "$mask" "$target")\""
        fi
        echo "variant: \"$variant\""
        echo "home: \"$addr\""
    } > "$dir/$addr.yml"

    echo "$clone=$addr"
}
