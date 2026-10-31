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

library bitvis_vip_avalon_st;
  context bitvis_vip_avalon_st.vvc_context;

library colibri;
  context colibri.common;

package misc_tb_pkg is

  -- 40 MHz Clock
  constant c_CLK_FREQ_40   : natural := 40e6;
  constant c_CLK_PERIOD_40 : time    := 1 sec / c_CLK_FREQ_40;
  constant c_CLK_40        : natural := 0;
  -- avalon interfaces
  constant c_DATA_WIDTH    : positive                                    := 32;
  subtype  t_avst_if is t_avalon_st_if(
  channel (0 downto 0),                           -- Channel number for data being transferred on the current cycle.
  data_error(0 downto 0),
  data (c_DATA_WIDTH - 1 downto 0),               -- Data. Width is constrained when the procedure is called.
  empty (log2ceil(c_DATA_WIDTH / 8) - 1 downto 0) -- Number of symbols that are empty (not valid).
  );
  constant c_AV_ST_SRC_IDX : natural                                     := 0;
  constant c_AV_ST_SNK_IDX : natural                                     := 1;
  constant c_HEADER        : std_logic_vector(c_DATA_WIDTH - 1 downto 0) := 32x"BADC0FFE";
  constant c_HEADER_SIZE   : natural                                    := 3;
  -- Define the default value for the BFM config
  constant c_AVST_CONFIG : t_avalon_st_bfm_config :=
  (
    max_wait_cycles          => 100,
    max_wait_cycles_severity => ERROR,
    clock_period             => c_CLK_PERIOD_40,
    clock_period_margin      => 0 ns,
    clock_margin_severity    => TB_ERROR,
    setup_time               => -1 ns,
    hold_time                => -1 ns,
    bfm_sync                 => SYNC_ON_CLOCK_ONLY,
    match_strictness         => MATCH_EXACT,
    symbol_width             => 8,
    first_symbol_in_msb      => true,
    max_channel              => 0,
    use_packet_transfer      => true,
    id_for_bfm               => ID_BFM
  );

  --   helpers
  function fill_array (n_bytes : natural) return t_slv_array;

  function add_header (arr : t_slv_array) return t_slv_array;

  function add_tailer (arr : t_slv_array) return t_slv_array;

end package misc_tb_pkg;

package body misc_tb_pkg is

  function fill_array (n_bytes : natural) return t_slv_array is

    variable v_res : t_slv_array(n_bytes - 1 downto 0)(7 downto 0);

  begin

    for i in 0 to n_bytes - 1 loop
      v_res(i) := std_logic_vector(to_unsigned((i mod 256), 8));
    end loop;

    return v_res;

  end function;

  function add_header (arr : t_slv_array) return t_slv_array is

    variable v_res : t_slv_array(arr'left + c_HEADER_SIZE downto 0)(7 downto 0);

  begin

    for i in 0 to c_HEADER_SIZE - 1 loop
      v_res(v_res'left - i) := c_HEADER(c_HEADER'left - (i * 8) downto c_HEADER'length - (i + 1) * 8);
    end loop;

    for i in 0 to arr'length - 1 loop
      v_res(v_res'left - i - c_HEADER_SIZE) := arr(arr'left - i);
    end loop;

    return v_res;

  end function;

  function add_tailer (arr : t_slv_array) return t_slv_array is

    variable v_res : t_slv_array(arr'left + c_HEADER_SIZE downto 0)(7 downto 0);

  begin

    for i in 0 to arr'length - 1 loop
      v_res(v_res'left - i) := arr(arr'left - i);
    end loop;

    for i in 0 to c_HEADER_SIZE - 1 loop
      v_res(c_HEADER_SIZE - 1 - i) := c_HEADER(c_HEADER'left - (i * 8) downto c_HEADER'length - (i + 1) * 8);
    end loop;

    return v_res;

  end function;

end package body misc_tb_pkg;
