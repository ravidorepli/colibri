<!--
SPDX-FileCopyrightText: 2026 CERN

SPDX-License-Identifier: CERN-OHL-W-2.0
-->

# Interfaces Packages and Entities

This directory contains different entities for interacting with interfaces.

### Stream Entities

Under the [stream/](stream/) folder:
- `avst_cdc` simple AvST clock domain crossing buffer.
- `avst_fifo` FIFO for Avalon-ST.
- `avst_to_axis` convert an Avalon STREAMING interface into an AXI Stream interface.
- `avst_width_converter` Avalon-ST data width converter.
- `axis_to_avst` convert an AXI Stream interface into an Avalon STREAMING interface.
- `avst_ram_write_unaligned` Avalon Stream to RAM writer with unaligned (byte-addressable) access
- `avst_ram_write` simple Avalon Stream to RAM writer
- `avst_ram_read_unaligned` Avalon Stream to RAM reader with unaligned (byte-addressable) access
- `avst_ram_read` simple Avalon Stream to RAM reader

Under the [memory_mapped/](memory_mapped/) folder:
- `wb_ram` a simple RAM with a light wishbone.B4 interface.

### How to use

Compile everything in the `colibri` library.  

### Development status and testing

| entity                        | simulation | self-checking tb | formal verification |
| ----------------------------- | ---------- | ---------------- | ------------------- |
| `stream/avst_cdc`             | ✅         | ✅              | ❌                 |
| `stream/avst_fifo`            | ✅         | ✅              | ❌                 |
| `stream/avst_to_axis`         | ✅         | ✅              | ✅                 |
| `stream/avst_width_converter` | ✅         | ✅              | ❌                 |
| `stream/axis_to_avst`         | ✅         | ✅              | ✅                 |
| `avst_ram_write_unaligned`    | ✅         | ✅              | ✅                 |
| `stream/avst_ram_write`       | ✅         | ✅              | ❌                 |
| `avst_ram_read_unaligned`     | ✅         | ✅              | ❌                 |
| `stream/avst_ram_read`        | ✅         | ✅              | ❌                 |
| `memory_mapped/wb_ram`        | ✅         | ✅              | ❌                 |
