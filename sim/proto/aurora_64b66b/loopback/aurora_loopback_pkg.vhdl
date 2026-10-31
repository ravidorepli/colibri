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

library colibri;
  use colibri.utils.all;
  use colibri.aurora_const.all;

library bitvis_vip_avalon_st;
  context bitvis_vip_avalon_st.vvc_context;

package aurora_loopback_pkg is

  -- Elink Clock
  constant CLK_FREQ_ELINK   : natural := 40e6;
  constant CLK_PERIOD_ELINK : time    := 1 sec / CLK_FREQ_ELINK;
  constant CLK_ELINK        : natural := 0;
  -- Avalon Clock
  constant CLK_FREQ_AVALON   : natural := CLK_FREQ_ELINK;
  constant CLK_PERIOD_AVALON : time    := 1 sec / CLK_FREQ_AVALON;
  constant CLK_AVALON        : natural := 2;
  -- avalon interfaces
  subtype  t_avst_if is t_avalon_st_if(
  channel (0 downto 0),                                  -- Channel number for data being transferred on the current cycle.
  data_error(0 downto 0),
  data (c_AURORA_DATA_WIDTH - 1 downto 0),               -- Data. Width is constrained when the procedure is called.
  empty (log2ceil(c_AURORA_DATA_WIDTH / 8) - 1 downto 0) -- Number of symbols that are empty (not valid).
  );
  constant AURORA_TX_IDX : natural := 0;
  constant AURORA_RX_IDX : natural := 1;

  -- Define the default value for the BFM config
  constant c_AVST_CONFIG : t_avalon_st_bfm_config :=
  (
    max_wait_cycles          => 1000000,
    max_wait_cycles_severity => ERROR,
    clock_period             => -1 ns,
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

  function fill_array (n_bytes : natural) return t_slv_array;

end package aurora_loopback_pkg;

package body aurora_loopback_pkg is

  function fill_array (n_bytes : natural) return t_slv_array is

    variable res : t_slv_array(n_bytes - 1 downto 0)(7 downto 0);

  begin

    for i in 0 to n_bytes - 1 loop
      res(i) := std_logic_vector(to_unsigned((i mod 256), 8));
    end loop;

    return res;

  end function fill_array;

end package body aurora_loopback_pkg;
