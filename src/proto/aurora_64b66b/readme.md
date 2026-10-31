<!--
SPDX-FileCopyrightText: 2026 CERN

SPDX-License-Identifier: CERN-OHL-W-2.0
-->

# Aurora 64b/66b

This directory contains an implementation of the [Aurora 64b/66b](https://docs.amd.com/v/u/en-US/aurora_64b66b_protocol_spec_sp011) specification.  

This aurora TX and RX entities support:
- 64 bit stream <---> any-width aurora encoded stream
- Simplex transmission
- Channel Bonding


### Entities Generics
Custom number of lanes (`g_N_LANES`) and lane width (`g_LANE_WIDTH`) can be set by the user.

Check for any backpressure in simulation, use `g_GBX_BUF_SIZE` to change gearbox buffer to ensure functionality.

For the RX side, there is the `g_USE_OPTIMIZED_GBX` generic set to `true` by default. With this condition, the RX will use the resource optimized continuous gearbox which is present in the [rx](./rx/) folder.  
This gearbox reduces the resource usage from ~700 LUTs (gearbox + slip_buffer) to ~200 LUTs on Xilinx Ultrascale+ devices.  
However, pay attention that this gearbox does not support backpressure (`ready` signal) and it is designed for continuous operation (last N words in could not be outputed until the buffer is full enough).

If you experience data corruption or link instability, you might be required to tune the `block_sync_fsm` generics `g_SH_INVALID_CNT_MAX` and `g_SH_CNT_MAX`.


### Advanced Usage
Encoder and Decoder support dual clock operation, this could be used to tune the bandwidth of the system to ensure maximum throughput.