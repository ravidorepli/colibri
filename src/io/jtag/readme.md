<!--
SPDX-FileCopyrightText: 2026 CERN

SPDX-License-Identifier: CERN-OHL-W-2.0
-->

# JTAG Streaming Interface

This entity enables the user to communicate with the design over the common JTAG interface.

## How To Use
Vendors usually provide JTAG primitives with USERx Boundary Scan Registers (BSRs) that can be connected to user logic.  
This entity connects to these primitives and uses the Data Register (DR) to exchange data with the design.
Together with the [misc/stream_to_wbm](../../misc/stream_to_wbm.vhdl) entity, the interface can be used to interact with memory-mapped interfaces.

| Signal                | Description                                                                                                     |
| --------------------- | --------------------------------------------------------------------------------------------------------------- |
| `drck`/`clkdruser`    | Gated Clock, active when JTAG FSM is in CAPTURE or SHIFT. In Altera only active with `USERx` register selected. |
| `sel`/`usr1user`      | USER Register Select. Active HIGH in Xilinx. '0' indicates `USER0` and '1' `USER1` in Altera                    |
| `shift`/`shiftuser`   | FSM SHIFT state                                                                                                 |
| `update`/`updateuser` | FSM UPDATE state                                                                                                |
| `tdi`/`tdiutap`       | Test Data Input (sampled on rising edge)                                                                        |
| `tdo`/`tdouser`       | Test Data Output (sampled on falling edge)                                                                      |




### AMD/Xilinx Vivado

Xilinx offers the **BSCANE2** JTAG BSR primitive. This primitive can be instantiated in any design using 7-series/Utrascale/Ultrascale+ FPGAs.
Up to 4 primitives can be initialized on the device using the 4 [USERx registers](https://docs.amd.com/r/en-US/ug570-ultrascale-configuration/Instruction-Register):

| Register Name | IR code (5:0) |
| ------------- | ------------- |
| USER1         | 0x02          |
| USER2         | 0x03          |
| USER3         | 0x22          |
| USER4         | 0x23          |

Here is an instantiation example:

```vhdl
  bscane2_inst : entity work.bscane2
    generic map (
      JTAG_CHAIN => 4 -- USER4 register
    )
    port map (
      capture => open,
      drck    => gck,
      reset   => open,
      runtest => open,
      sel     => sel,
      shift   => shift,
      tck     => tck,
      tdi     => tdi,
      tms     => open,
      update  => update,
      tdo     => tdo
    );

  jtag_serdes_inst : entity work.jtag_serdes
    generic map (
      g_DATA_WIDTH => 40
    )
    port map (
      clk_ser_i   => gck,
      clk_par_i   => sys_clk,
      shift_i     => shift and sel,
      update_i    => update and sel,
      par_data_i  => ps_data,
      par_valid_i => ps_valid,
      par_data_o  => sp_data,
      par_valid_o => sp_valid,
      ser_data_i  => tdi,
      ser_data_o  => tdo
    );
```

### Altera/Intel Quartus

Altera offers a similar set of JTAG primitives which are family-specific.
Altera JTAG has only two USERx registers:

| Register Name | IR Code (9:0) |
| ------------- | ------------- |
| USER0         | 0x00C         |
| USER1         | 0x00E         |

The components' declarations can be found in `<QUARTUS_ROOTDIR>/libraries/vhdl/<FAB_NODE>/<LIBNAME>.vhd`, where `FAB_NODE` is the fabrication node/FPGA family which is usually also the component prefix.


Here is an example for Arria 10 devices (20nm node):
```vhdl
  jtag_if : component twentynm_jtag
    port map (
      -- MAIN JTAG I/O IF
      ntrst   => altera_reserved_ntrst,
      tck     => altera_reserved_tck,
      tms     => altera_reserved_tms,
      tdi     => altera_reserved_tdi,
      tdo     => altera_reserved_tdo,
      corectl => '0',
      -- main jtag replication
      tckutap => tck,
      tdiutap => tdi,
      -- user interface
      clkdruser   => gck,
      usr1user    => sel,
      runidleuser => open,
      shiftuser   => shift,
      updateuser  => update,
      tdouser     => tdo
    );

  jtag_serdes_inst : entity work.jtag_serdes
    generic map (
      g_data_width => 40
    )
    port map (
      clk_ser_i   => gck,
      clk_par_i   => sys_clk,
      shift_i     => shift and sel,
      update_i    => update and sel,
      par_data_i  => ps_data,
      par_valid_i => ps_valid,
      par_data_o  => sp_data,
      par_valid_o => sp_valid,
      ser_data_i  => tdi,
      ser_data_o  => tdo
    );
```

## Interact with the core

Using `openocd` it is possible to interact directly from the CLI with the core.
- Configure your JTAG adapter and create a jtag TAP definition with the correct IR length (6 for Xilinx, 10 for Altera).
- Move to the USERx IR register with `irscan <YOUR_TAP> <IR_CODE>` (e.g. `irscan xcau25.tap 0x23`)
- Shift your data in with `drscan <YOUR_TAP> <N_BITS> <DATA_IN_HEX>` (e.g. `drscan xcau25.tap 40 0x0102030405`). drscan will return the equivalent number of bits shifted out from the core (e.g. your user data).  

Simple Python abstraction libraries are available in the [utils/jtag](../../../utils/jtag/) folder.

---
## References
[Tom Verbeure's Blog](https://tomverbeure.github.io/2021/10/30/Intel-JTAG-Primitive.html)  
[BSCANE2 Primitive](https://docs.amd.com/r/en-US/ug570-ultrascale-configuration/BSCANE2)  
[urJtag FJMEM](https://github.com/shuckc/urjtag/tree/master/urjtag/extra/fjmem)  