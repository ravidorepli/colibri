-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library vunit_lib;
  context vunit_lib.vunit_context;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_clock_generator;
  context bitvis_vip_clock_generator.vvc_context;

library bitvis_vip_axistream;
  context bitvis_vip_axistream.vvc_context;

library bitvis_vip_spi;
  context bitvis_vip_spi.vvc_context;

library colibri;
  context colibri.common;

package tb_pkg is

  -- 40 MHz Clock
  constant c_CLK_FREQ_40   : natural  := 40e6;
  constant c_CLK_PERIOD_40 : time     := 1 sec / c_CLK_FREQ_40;
  constant c_CLK_40        : natural  := 0;
  constant c_BAUD_RATE     : natural  := 1e6;
  constant c_DATA_WIDTH    : positive := 8;

  -- interfaces

  constant c_SPI_IDX : natural := 1;


  constant c_AXIS_CONF : t_axistream_bfm_config :=
  (
    max_wait_cycles                => 1000000,
    max_wait_cycles_severity       => ERROR,
    clock_period                   => -1 ns,
    clock_period_margin            => 0 ns,
    clock_margin_severity          => TB_ERROR,
    setup_time                     => -1 ns,
    hold_time                      => -1 ns,
    bfm_sync                       => SYNC_ON_CLOCK_ONLY,
    match_strictness               => MATCH_EXACT,
    byte_endianness                => LOWER_BYTE_LEFT,
    valid_low_at_word_num          => 0,
    valid_low_multiple_random_prob => 0.5,
    valid_low_duration             => 0,
    valid_low_max_random_duration  => 5,
    check_packet_length            => false,
    protocol_error_severity        => ERROR,
    ready_low_at_word_num          => 0,
    ready_low_multiple_random_prob => 0.5,
    ready_low_duration             => 0,
    ready_low_max_random_duration  => 5,
    ready_default_value            => '0',
    id_for_bfm                     => ID_BFM
  );

  subtype  t_axis_if is t_axistream_if(
    tdata  (c_DATA_WIDTH - 1 downto 0),     -- Data. Width is constrained when the procedure is called
    tkeep  (c_DATA_WIDTH / 8 - 1 downto 0), -- One valid-bit per data byte
    tuser  (0 downto 0),                    -- User sideband data
    tstrb (c_DATA_WIDTH / 8 - 1 downto 0),  -- Treated as sideband data by BFM: tstrb does not affect tdata
    tid   (0 downto 0),                     -- Treated as sideband data by BFM
    tdest (0 downto 0)                      -- Treated as sideband data by BFM
);
  constant c_AXIS_SRC_IDX : natural := 2;
  constant c_AXIS_SNK_IDX : natural := 3;

end package tb_pkg;

package body tb_pkg is

end package body tb_pkg;
