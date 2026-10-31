<!--
SPDX-FileCopyrightText: 2026 CERN

SPDX-License-Identifier: CERN-OHL-W-2.0
-->

# Miscellaneous Entities

This directory contains different entities that aren't grouped in any other collection.

### Entities

- `be_add_lead` add leading word (header) to AvST packet and shift the rest forward. It is a more complete implementation of the old `be_shifter` which was only supporting shifting.

- `be_add_trail` add trailing word (tailer) to the AvST packet and updates the empty count. Useful to add CRC calculations to packets.

- `be_remove_head` remove leading word (header) from the AvST packet and updates the empty count. Useful to get headers from packets.

- `be_remove_trail` remove trailing word (tailer) from the AvST packet and updates the empty count. Useful to get CRC fields from packets.

- `mmap_fifo` Memory Mapped to/from Stream FIFO. Interfaces a Wishbone Bus to full duplex AvST packet streams, single directions are possible using the `mmap_fifo_tx` or `mmap_fifo_rx`. To use these entities, generate the correspondent VHDL RDL registers [[See Section Below](#Generate-Register-Maps)]. The entities use `cc_fifo` by default. The user can select RAM-based FIFO by using the generic `g_USE_BLOCK_RAM`. Check RAM-based [FIFO usage options](../memory/readme.md#notes-on-resource-efficiency).

- `heartbeat` a simple counter module that provides a divided-down heartbeat signal for a clock.

- `powerup_reset` a module used to manage power-up reset sequences

- `stream_to_wbm` a module to access memory mapped slaves (using Wishbone B4) from a bidirectional stream. Useful to access configuration and status registers over UART.

- `frequency counter` a module that measures frequencies of arbitrary clocks against a known reference.

### Development status and testing

| entity              | simulation | self-checking tb | formal verification |
| ------------------- | ---------- | ---------------- | ------------------- |
| `be_add_lead`       | ✅          | ✅                | ✅                   |
| `be_add_trail`      | ✅          | ✅                | ✅                   |
| `be_remove_lead`    | ✅          | ✅                | ✅                   |
| `be_remove_trail`   | ✅          | ✅                | ✅                   |
| `be_remove_trail`   | ✅          | ✅                | ✅                   |
| `mmap_fifo_tx`      | ✅          | ✅                | ❌                   |
| `mmap_fifo_rx`      | ✅          | ✅                | ❌                   |
| `mmap_fifo`         | ✅          | ✅                | ❌                   |
| `heartbeat`         | ✅          | ✅                | ❌                   |
| `powerup_reset`     | ✅          | ✅                | ❌                   |
| `stream_to_wbm`     | ✅          | ✅                | ❌                   |
| `frequency_counter` | ✅          | ✅                | ❌                   |

### Generate Register Maps
By default, cpuif passtrough interfaces for `mmap_fifo` are available in [mmap_fifo/vhdl_if](mmap_fifo/vhdl_if/).
To generate VHDL entities and packages required for `mmap_fifo*` entities with different settings, use `peakrdl` with `regblock-vhdl` exporter.

*Note: The required `pip` packages are specified in [mmap_fifo/requirements.txt](mmap_fifo/requirements.txt)*

```
peakrdl regblock-vhdl -o ./vhdl_if --cpuif passthrough --addr-width 32 --copy-utils-pkg ./mmap_fifo_tx.rdl 
peakrdl regblock-vhdl -o ./vhdl_if --cpuif passthrough --addr-width 32 --copy-utils-pkg ./mmap_fifo_rx.rdl 
peakrdl regblock-vhdl -o ./vhdl_if --cpuif passthrough --addr-width 32 --copy-utils-pkg ./mmap_fifo.rdl
for f in vhdl_if/*.vhd; do mv "$f" "${f%.txt}.vhdl"; done
```

