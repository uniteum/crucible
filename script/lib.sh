#!/usr/bin/env bash
# crucible/script/lib.sh — shared CREATE2-input helpers for the
# predict/mine pipeline.
#
# Source this from clone.sh (prediction) or a mining script. It defines
# the canonical EIP-1167 initcode and arg-encoding formulas in one place
# so prediction and mining can never drift apart.
#
# Sourcing this file does NOT cd anywhere — the sourcing script owns cwd.

# clone_proxy_initcode <deployer>
#
# Echo the EIP-1167 minimal-proxy initcode that <deployer> (a Bitsy
# prototype) deploys for each of its clones. keccak256 of this is the
# CREATE2 init-code hash shared by every clone of that prototype.
clone_proxy_initcode() {
    local deployer="$1"
    printf '0x3d602d80600a3d3981f3363d3d373d3d3d363d73%s5af43d82803e903d91602b57fd5bf3' "${deployer#0x}"
}

# clone_args_bytes <argstype> <argsValue>...
#
# Echo the abi-encoded `bytes` blob a Bitsy `make(<argstype>, uint256)`
# call forwards to zzInit. keccak256 of this is the argshash that
# Prototype.made XORs with `variant` to form the CREATE2 salt.
clone_args_bytes() {
    local argstype="$1"
    shift
    cast abi-encode "f($argstype)" "$@"
}

# saltminer_url <deployer> <initcodehash> <argshash> <mask> <target>
#
# Echo a prefilled saltbounty.com link that mines a vanity address for these
# CREATE2 inputs. saltbounty.com is the in-browser (WebGPU) port of saltminer:
# open the link, click "mine", and it reports the matching salt — which is the
# `variant` for a clone (argshash set) or the `salt` for a prototype (argshash
# all-zero). Captured into the yml so the mining inputs travel with the
# deployment metadata and can never drift from the predicted address.
saltminer_url() {
    printf 'https://saltbounty.com/#deployer=%s&initcodehash=%s&argshash=%s&mask=%s&target=%s&min=0&max=0xffffffffffffffff&dispatch=1048576' \
        "$1" "$2" "$3" "$4" "$5"
}

# mine_clone <deployer> <argstype> <argsValue>...
#
# Vanity-mine a `variant` for a Bitsy clone deployed by <deployer>'s
# make() call. Reads the target pattern from the `mask`/`target` env
# vars (the same convention clone_predict captures into the yml) and
# shells out to saltminer, which prints the matching `salt` — for a
# clone that printed value is the `variant` to pass to make() — and the
# resulting `home`.
mine_clone() {
    local deployer="$1"
    local argstype="$2"
    shift 2

    : "${mask:?mine_clone: set the mask env var}"
    : "${target:?mine_clone: set the target env var}"

    local initcodehash
    initcodehash=$(cast keccak "$(clone_proxy_initcode "$deployer")")
    local argshash
    argshash=$(cast keccak "$(clone_args_bytes "$argstype" "$@")")

    echo "mine_clone: deployer=$deployer initcodehash=$initcodehash argshash=$argshash" >&2

    saltminer \
        --deployer "$deployer" \
        --initcodehash "$initcodehash" \
        --argshash "$argshash" \
        --mask "$mask" \
        --target "$target"
}
