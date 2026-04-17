#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin="$repo_root/zenoh.lua"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

assert_contains() {
    local file="$1"
    local pattern="$2"

    if ! grep -Fq "$pattern" "$file"; then
        echo "Expected to find pattern in $(basename "$file"): $pattern" >&2
        exit 1
    fi
}

run_capture() {
    local capture="$1"
    shift

    local out
    out="$(mktemp "$tmpdir/$(basename "$capture").XXXXXX")"

    HOME="$tmpdir/home" \
    XDG_CONFIG_HOME="$tmpdir/config" \
    tshark -r "$repo_root/$capture" -X "lua_script:$plugin" -Y zenoh -V >"$out"

    for pattern in "$@"; do
        assert_contains "$out" "$pattern"
    done

    echo "ok  $(basename "$capture")"
}

require_cmd luac
require_cmd tshark

luac -p "$plugin"
echo "ok  zenoh.lua syntax"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/home" "$tmpdir/config"

run_capture \
    "assets/pubsub.pcapng" \
    "Transport: INIT (InitSyn)" \
    "Patch Version: 1" \
    "Declaration: D_KEYEXPR" \
    "Declaration: D_SUBSCRIBER" \
    "Key Expression (resolved): demo/example/zenoh-rs-pub" \
    "Payload (omitted):"

run_capture \
    "assets/pubsub-couple.pcapng" \
    "Transport: INIT (InitSyn)" \
    "Session Source ZID:" \
    "Declaration: D_KEYEXPR" \
    "Declaration: D_SUBSCRIBER" \
    "Key Expression (resolved): demo/example/zenoh-rs-pub" \
    "Payload (omitted):"

run_capture \
    "assets/sample-data.pcap" \
    "Transport: INIT (InitSyn)" \
    "Session Source ZID:" \
    "Declaration: D_KEYEXPR" \
    "Declaration: D_SUBSCRIBER" \
    "Key Expression (resolved): demo/example/zenoh-rs-put" \
    "Payload (omitted):"

echo "All regression checks passed."
