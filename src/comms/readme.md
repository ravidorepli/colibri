<!--
SPDX-FileCopyrightText: 2026 CERN

SPDX-License-Identifier: CERN-OHL-W-2.0
-->

# Communication Entities

This directory contains different entities used in communications.

### Entities

- `scrambler` self-synchronous scrambler (multiplicative).
- `descrambler` self-synchronous descrambler (multiplicative).
- `slip_buffer` slip buffer for synchronization of a data stream.
- `cc_gearbox` dual clock generic gearbox for any data width.
- `gearbox` simple single clock gearbox for any data width.
- `crc` Cyclic Redundancy Check for packet streams.
- `bert` PRBS-based Bit Error Rate Tester.
- `bit_shifter` Bit-shift a stream of data
### Development status and testing

| entity        | simulation         | self-checking tb   | formal verification |
| ------------- | ------------------ | ------------------ | ------------------- |
| `scrambler`   | ✅ | ✅ | ❌                 |
| `descrambler` | ✅ | ✅ | ❌                 |
| `slip_buffer` | ✅ | ✅ | ❌                 |
| `cc_gearbox`  | ✅ | ✅ | ❌                 |
| `gearbox`     | ✅ | ✅ | 🟡     |
| `crc`        | ✅ | ✅ | ❌                 |
| `bert`        | ✅ | ✅ | ❌                 |
| `bit_shifter` | ✅ | ✅ | ❌                 |

### About Gearboxes

Use `cc_gearbox` for applications that require dual clocks.

`cc_gearbox` achieves maximum throughput when the internal FIFO buffer is sized correctly, test in simulation which setup gives the appropriate performance for your application.
`cc_gearbox` uses `cc_fifo` by default. The user can select RAM-based FIFO by using the generic `g_USE_BLOCK_RAM`. Check RAM-based [FIFO usage options](../memory/readme.md#notes-on-resource-efficiency).

### Use as PRBS

Scrambler and descrambler enities can be used as PRBS Generator and Checker:
- Use PRBS polynomials available in [poly](utils/poly_pkg.vhdl)
- Set the init value to random seed (not all 0 or all 1)
- Use a signature word as input (random choice)
- Check that received word matches the signature

Check [sim/prbs_tb](../../sim/comms/prbs_tb.vhdl) as example.