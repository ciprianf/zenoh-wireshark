# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project overview

A Wireshark Lua dissector for the [Zenoh protocol](https://spec.zenoh.io). The entire implementation lives in a single file: `zenoh.lua`. There is no build system — the file is installed by copying it to the platform-specific Wireshark Lua plugins directory.

The dissector currently registers under the abbreviation `zenoh` (display name **Zenoh Protocol (Lua)**).

## Testing the dissector

Run against a sample capture without installing:

```sh
tshark -r assets/pubsub.pcapng -X lua_script:zenoh.lua -Y zenoh -V
bash tests/regression.sh
```

Reload in a running Wireshark instance (no restart needed):

```
Analyze → Reload Lua Plugins  (Ctrl+Shift+L)
```

## Architecture of `zenoh.lua`

The file is organized into 13 sequential sections that must remain in order (Lua requires definitions before use):

1. **Protocol object** — `zenoh_proto` with the `zenoh` abbreviation.
2. **Value-string tables** — lookup tables mapping numeric IDs to names for message types, flags, and extensions at each protocol layer (transport, network, scouting).
3. **ProtoField definitions** — all `ProtoField` declarations registered with `zenoh_proto.fields`; adding a new field requires an entry here and a call to `subtree:add()` in the relevant parser.
4. **Helper functions** — `read_vle()` (LEB128 integer decoding), string/byte readers, `parse_extensions()` (extension-chain walker), `parse_timestamp()`, and cross-packet key/ZID helpers.
5. **Data sub-message parsers** — `dissect_put`, `dissect_del`, `dissect_query`, `dissect_reply`, `dissect_err`.
6. **Declaration parsers** — `parse_wire_expr()` (key expression from headers), `dissect_declaration()` (dispatches all D_/U_ variants).
7. **Network message parsers** — `dissect_network_msg()` plus message-specific extension helpers/spec tables.
8. **Transport message parsers** — `dissect_init`, `dissect_open`, `dissect_close`, `dissect_keep_alive`, `dissect_join`, and the FRAME/FRAGMENT/OAM branches inside `dissect_transport_msg()`.
9. **Transport-layer batch dissector** — `dissect_transport_msg()` dispatches the message stream within one TCP frame or UDP datagram.
10. **Scouting message parsers** — `parse_scout`, `parse_hello`.
11. **Main dissector entry points** — TCP dissector uses a 2-byte little-endian length prefix for desegmentation; UDP dissector calls `dissect_zenoh_frame()` directly (one datagram = one batch).
12. **Port registration** — TCP 7447; UDP 7446, 7447, 7448.
13. **Heuristic dissection** — TCP and UDP heuristics recognise transport traffic on non-standard ports and lock the conversation once accepted.

### Key encoding conventions

- **VLE (Variable-Length Encoding)**: LEB128 — the low 7 bits of each byte are data, bit 7 indicates "more bytes follow". Decoded by `read_vle()`.
- **z-int sizes**: `z8`, `z16`, `z32`, `z64` variants appear throughout header parsing.
- **TCP framing**: each batch is prefixed by a 2-byte little-endian length; `DissectorTable` handles stream reassembly.
- **Message header byte**: low 5 bits = message ID, bits 5–7 = flags (A/B/Z or similar per message type).
- **Extensions**: chained after the fixed header when the Z flag is set; each extension header is `|Z|ENC|M|ID|` with a 4-bit ID, a mandatory bit, 2 encoding bits, and a "more extensions" bit. Parsed by `parse_extensions()`.

### Protocol spec

The authoritative wire-format reference is the [Zenoh draft specification](https://spec.zenoh.io). Two local Rust implementations serve as the ground-truth reference when the spec is ambiguous:

- **zenoh-rust**: `/Users/kydos/yukido/labs/zenoh-rust/commons/zenoh-protocol` — the main Zenoh Rust codebase; codec logic lives here.
- **zenoh-nostd**: `/Users/kydos/yukido/labs/zenoh-nostd/crates/zenoh-proto` — a `no_std`-compatible protocol implementation; often the clearest source for wire-format details.

### Sample captures

`assets/` holds `.pcap`/`.pcapng` files used for manual verification and by `tests/regression.sh`. Prefer `pubsub.pcapng` for general testing and `pubsub-couple.pcapng` for multi-node scenarios.
