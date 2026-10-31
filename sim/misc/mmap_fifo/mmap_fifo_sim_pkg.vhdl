-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  context colibri.common;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_avalon_st;
  context bitvis_vip_avalon_st.vvc_context;

library bitvis_vip_wishbone;
  context bitvis_vip_wishbone.vvc_context;

package mmap_fifo_sim_pkg is

  -- Clock period
  constant c_WB_CLK_PERIOD : time := 20 ns;
  constant c_CLK_PERIOD    : time := 50 ns;
  -- Generics
  constant c_WB_ADDR_WIDTH     : natural := 32;
  constant c_WB_DATA_WIDTH     : natural := 32;
  constant c_STREAM_DATA_WIDTH : natural := c_WB_DATA_WIDTH;
  constant c_NUM_WORDS         : natural := 16;
  constant c_NUM_CH            : natural := 4;

  -- VVC
  -- avalon interfaces
  subtype t_avst_if is t_avalon_st_if(
  channel (log2ceil(c_NUM_CH) - 1 downto 0),             -- Channel number for data being transferred on the current cycle.
  data_error(0 downto 0),
  data (c_STREAM_DATA_WIDTH - 1 downto 0),               -- Data. Width is constrained when the procedure is called.
  empty (log2ceil(c_STREAM_DATA_WIDTH / 8) - 1 downto 0) -- Number of symbols that are empty (not valid).
  );

  subtype t_wbm_if is t_wishbone_if(adr_o(c_WB_ADDR_WIDTH - 1 downto 0),
                                  dat_o(c_WB_DATA_WIDTH - 1 downto 0),
                                  dat_i(c_WB_DATA_WIDTH - 1 downto 0));

  constant c_AVST_MM2S : natural := 0;
  constant c_AVST_S2MM : natural := 1;
  constant c_CLK_MAIN  : natural := 2;
  constant c_CLK_WB    : natural := 3;
  constant c_WBM       : natural := 4;

  -- Define the default value for the BFM config
  constant c_AVST_CONFIG : t_avalon_st_bfm_config :=
  (
    max_wait_cycles          => 1000,
    max_wait_cycles_severity => ERROR,
    clock_period             => c_CLK_PERIOD,
    clock_period_margin      => 0 ns,
    clock_margin_severity    => TB_ERROR,
    setup_time               => c_CLK_PERIOD / 4,
    hold_time                => c_CLK_PERIOD / 4,
    bfm_sync                 => SYNC_ON_CLOCK_ONLY,
    match_strictness         => MATCH_EXACT,
    symbol_width             => 8,
    first_symbol_in_msb      => true,
    max_channel              => c_NUM_CH,
    use_packet_transfer      => true,
    id_for_bfm               => ID_BFM
  );

  constant c_WBM_CONFIG : t_wishbone_bfm_config :=
  (
    max_wait_cycles          => 100,
    max_wait_cycles_severity => failure,
    clock_period             => c_WB_CLK_PERIOD,
    clock_period_margin      => 0 ns,
    clock_margin_severity    => TB_ERROR,
    setup_time               => c_WB_CLK_PERIOD / 4,
    hold_time                => c_WB_CLK_PERIOD / 4,
    match_strictness         => MATCH_EXACT,
    id_for_bfm               => ID_BFM,
    id_for_bfm_wait          => ID_BFM_WAIT,
    id_for_bfm_poll          => ID_BFM_POLL
  );

  function to_byte_array (vec : std_logic_vector) return t_slv_array;

end package mmap_fifo_sim_pkg;

package body mmap_fifo_sim_pkg is

  function to_byte_array (vec : std_logic_vector) return t_slv_array is

    variable v_res : t_slv_array(0 to vec'length / 8 - 1)(7 downto 0);

  begin

    for i in 0 to (vec'length / 8) - 1 loop
      v_res(i) := vec(vec'left - i * 8 downto vec'length - (i + 1) * 8);
    end loop;

    return v_res;

  end function to_byte_array;

end package body mmap_fifo_sim_pkg;
