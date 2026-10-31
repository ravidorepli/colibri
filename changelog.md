<!--
SPDX-FileCopyrightText: 2026 CERN
SPDX-License-Identifier: Apache-2.0
-->

# Changelog

## Release 2026.07
New Components:


Updated components:

- Fixed I2C master issues when multi-byte write and consequent read write ops. (!89 !90)
- Handle multi-lane misconfiguration in aurora 64b/66b decoder (!95)
- Improved ROM inference in 8B/10B LUT-based encoder/decoder (!96)
- Fixed packet_cc_ram_fifo corner cases (drop when not ready !97 single cycle packets !100)
- Fixed div_ceil possible overflow (!99)
- Add packet output to avst_ram_read (!99)
- Better handling of non-standard streams in avst_ram_write (!99)
- Better hangling of last_i in packet_join (!99)

Other changes:

- Add licensing tags !90
- Add OHWR repository docs !92
- Improve CI/CD !93 !94
- Include RDL-generated VHDL in repo !86 !88 !89

## Release 2026.05
New Components:
- Simple Stream Clock Domain Crossing [avst_cdc](/src/interfaces/stream/avst_cdc.vhdl) !57
- CDC handshake synchronizer [synchro_handshake](/src/common/synchro_handshake.vhdl) !65
- 8b/10b Encoder/Decoder [encdec](/src/endec) !67
- Comparator [comparator](/src/common/comparator.vhdl) !68
- CRC calculation [crc](/src/comms/crc.vhdl) !74
- JTAG boundary scan serdes [jtag_serdes](/src/io/jtag/jtag_serdes.vhdl) !75
- Clock Frequency Counter [frequency_counter](/src/misc/frequency_counter.vhdl) !76
- Packet stream joiner [packet_join](/src/packet/packet_join.vhdl) !77
- Packet stream to RAM read/write access [interface/stream](/src/interfaces/stream/) !77
- Packet stream delay [packet_delay](/src/packet/packet_delay.vhdl) !78
- Ring buffer [ring_buffer](/src/memory/ring_buffer.vhdl) !79
- Memory-mapped FIFO [mmap_fifo](/src/misc/mmap_fifo) !80
- RAM-based FIFO [cc_ram_fifo](/src/memory/cc_ram_fifo.vhdl) !82
- New Packet FIFO [packet_cc_ram_fifo](/src/memory/packet_cc_ram_fifo.vhdl) !84
- Generic implementations of skid/pipeline buffers [stream_buffer](/src/common/stream_buffer.vhdl) [stream_buffer_generic](/src/common/stream_buffer_generic.vhdl) !87



Updated Components:
- Optimized BRAM synthesis with mixed width support and byte-enables !58 !73 !81
- Dual Port RAM initialization !66
- Fix combinational loops in src/packet features !60
- Improved latency for FWFT FIFO mode !70
- Fix onehot encoder output !72
- Add write-side peek next read in FIFO !83


Other changes:
- Vivado Automated Resource Scan script [scan dir](/utils/vivado/scan/) !59
- Update style guide !61
- Procedures to interconnect different avalon stream types !62 !64
- Unify and improve Formal Verification tests and reports !63
- Array operations !71
- One line if-then-else initialization functions !71
- Utilities to access memory-mapped interfaces over JTAG !75