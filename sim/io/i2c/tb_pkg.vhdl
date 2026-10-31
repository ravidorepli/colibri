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

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_i2c;
  context bitvis_vip_i2c.vvc_context;

library colibri;
  context colibri.common;

package tb_pkg is

  -- 40 MHz Clock
  constant c_CLK_FREQ_40    : natural := 40e6;
  constant c_CLK_PERIOD_40  : time    := 1 sec / c_CLK_FREQ_40;
  constant c_CLK_40         : natural := 0;
  constant c_CLK_I2C_PERIOD : time    := 250 ns;
  -- avalon interfaces
  constant c_AVALON_SOURCE_STREAM : avalon_source_t :=
    new_avalon_source(data_length => 8, valid_high_probability => 1.0);
  constant c_MASTER_STREAM        : stream_master_t := as_stream(c_AVALON_SOURCE_STREAM);

  constant c_AVALON_SINK_STREAM : avalon_sink_t  :=
    new_avalon_sink(data_length => 8, ready_high_probability => 1.0);
  constant c_SLAVE_STREAM       : stream_slave_t := as_stream(c_AVALON_SINK_STREAM);

  constant c_I2C_IDX  : natural          := 0;
  constant c_I2C_CONF : t_i2c_bfm_config :=
  (
    enable_10_bits_addressing       => false,
    master_sda_to_scl               => c_CLK_I2C_PERIOD,
    master_scl_to_sda               => c_CLK_I2C_PERIOD,
    master_stop_condition_hold_time => c_CLK_I2C_PERIOD,
    max_wait_scl_change             => 10 ms,
    max_wait_scl_change_severity    => failure,
    max_wait_sda_change             => 10 ms,
    max_wait_sda_change_severity    => failure,
    i2c_bit_time                    => c_CLK_I2C_PERIOD,
    i2c_bit_time_severity           => failure,
    acknowledge_severity            => failure,
    slave_mode_address              => 10b"111011",
    slave_mode_address_severity     => failure,
    slave_rw_bit_severity           => failure,
    reserved_address_severity       => warning,
    match_strictness                => MATCH_EXACT,
    id_for_bfm                      => ID_BFM,
    id_for_bfm_wait                 => ID_BFM_WAIT,
    id_for_bfm_poll                 => ID_BFM_POLL
  );

  subtype i2c_if_t is t_i2c_if;

end package tb_pkg;

package body tb_pkg is

end package body tb_pkg;
