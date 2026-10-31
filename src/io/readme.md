<!--
SPDX-FileCopyrightText: 2026 CERN

SPDX-License-Identifier: CERN-OHL-W-2.0
-->

# I/O Entities

This directory contains entities for I/O manipulation.

### Entities

- `i2c`
    - `i2c_controller` A simple I2C controller (Master).
- `uart`
    - `uart` An UART transceiver.
    - `uart_rx` An UART receiver.
    - `uart_tx` An UART transmitter.
- `spi`
    - `spi_slave` An SPI slave.
    - `spi_master` An SPI master.
- `jtag`
    - `jtag_serdes` a JTAG compatible duplex streaming interface.
    
### Development status and testing

| entity           | simulation | self-checking tb | formal verification |
| ---------------- | ---------- | ---------------- | ------------------- |
| `i2c_controller` | ✅          | ✅                | ❌                   |
| `uart`           | ✅          | ✅                | ❌                   |
| `spi_slave`      | ✅          | ✅                | ❌                   |
| `spi_master`     | ✅          | ✅                | ❌                   |
| `jtag_serdes`    | ✅          | ✅                | ❌                   |
