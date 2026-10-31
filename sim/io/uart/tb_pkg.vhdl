-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.com_context;
  context vunit_lib.data_types_context;
  use vunit_lib.avalon_stream_pkg.all;
  use vunit_lib.stream_master_pkg.all;
  use vunit_lib.stream_slave_pkg.all;

library colibri;
  context colibri.common;

package tb_pkg is

  -- 40 MHz Clock
  constant c_CLK_FREQ_40    : natural := 40e6;
  constant c_CLK_PERIOD_40  : time    := 1 sec / c_CLK_FREQ_40;
  constant c_CLK_40         : natural := 0;
  constant c_CLK_I2C_PERIOD : time    := 250 ns;
  constant c_BAUD_RATE      : natural := 1e6;

  -- avalon interfaces
  constant c_AVALON_SOURCE_STREAM : avalon_source_t :=
    new_avalon_source(data_length => 8, valid_high_probability => 1.0);
  constant c_MASTER_STREAM        : stream_master_t := as_stream(c_AVALON_SOURCE_STREAM);

  constant c_AVALON_SINK_STREAM : avalon_sink_t  :=
    new_avalon_sink(data_length => 8, ready_high_probability => 1.0);
  constant c_SLAVE_STREAM       : stream_slave_t := as_stream(c_AVALON_SINK_STREAM);

end package tb_pkg;

package body tb_pkg is

end package body tb_pkg;
