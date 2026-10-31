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

package endec_loopback_pkg is

  constant N_LANES : positive := 4;
  -- 40 MHz Clock
  constant CLK_FREQ_LANE     : natural := 40e6;
  constant CLK_PERIOD_LANE   : time    := 1 sec / CLK_FREQ_LANE;
  constant CLK_LANE          : natural := 0;
  constant CLK_FREQ_AVALON   : natural := 40e6 * N_LANES;
  constant CLK_PERIOD_AVALON : time    := 1 sec / CLK_FREQ_AVALON;
  constant CLK_AVALON        : natural := 1;
  -- avalon interfaces
  subtype  t_avst_if is t_avalon_st_if(
  channel (0 downto 0),                                  -- Channel number for data being transferred on the current cycle.
  data_error(0 downto 0),
  data (c_AURORA_DATA_WIDTH - 1 downto 0),               -- Data. Width is constrained when the procedure is called.
  empty (log2ceil(c_AURORA_DATA_WIDTH / 8) - 1 downto 0) -- Number of symbols that are empty (not valid).
  );
  constant ENCODE_IDX : natural := 0;
  constant DECODE_IDX : natural := 1;

  function fill_array (n_bytes : natural) return t_slv_array;

end package endec_loopback_pkg;

package body endec_loopback_pkg is

  function fill_array (n_bytes : natural) return t_slv_array is

    variable res : t_slv_array(n_bytes - 1 downto 0)(7 downto 0);

  begin

    for i in 0 to n_bytes - 1 loop
      res(i) := std_logic_vector(to_unsigned((i mod 256), 8));
    end loop;

    return res;

  end function;

end package body endec_loopback_pkg;
