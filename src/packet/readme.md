<!--
SPDX-FileCopyrightText: 2026 CERN

SPDX-License-Identifier: CERN-OHL-W-2.0
-->

# Packet Entities

This directory contains entities that do operations on packeted streams.

### Entities

- [header_remover](./header_remover.vhdl) Fixed-size generic header remover.
- [header_adder](./header_adder.vhdl) Fixed-size generic header adder.
- [interleaver](./interleaver.vhdl) Many-to-one streams interleaver.
- [deinterleaver](./deinterleaver.vhdl) One-to-many streams deinterleaver.
- [broadcaster](./broadcaster.vhdl) One-to-many streams broadcaster.
- [packet_join](./packet_join.vhdl) Joins consecutive packets into one.
- [packet_delay](./packet_delay.vhdl) Delays packets by a configurable number of clock cycles


### Development status and testing

| entity           | simulation         | self-checking tb   | formal verification |
| ---------------- | ------------------ | ------------------ | ------------------- |
| `header_remover` | ✅ | ✅ | ✅  |
| `header_adder`   | ✅ | ✅ | ✅  |
| `interleaver`    | ✅ | ✅ | ✅  |
| `deinterleaver`  | ✅ | ✅ | ✅  |
| `broadcaster`    | ✅ | ✅ | ✅  |
| `packet_join`    | ✅ | ✅ | ✅  |
| `packet_delay`   | ✅ | ✅ | ✅  |
