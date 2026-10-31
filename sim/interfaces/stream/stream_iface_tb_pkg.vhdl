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

library bitvis_vip_axistream;
  context bitvis_vip_axistream.vvc_context;

library colibri;
  context colibri.common;

package stream_iface_tb_pkg is

  -- 40 MHz Clock
  constant c_CLK_FREQ_40   : natural := 40e6;
  constant c_CLK_PERIOD_40 : time    := 1 sec / c_CLK_FREQ_40;
  constant c_CLK_40        : natural := 0;
  -- avalon interfaces
  constant c_DATA_WIDTH : positive := 32;
  subtype  t_avst_if is t_avalon_st_if(
  channel (0 downto 0),                           -- Channel number for data being transferred on the current cycle.
  data_error(0 downto 0),
  data (c_DATA_WIDTH - 1 downto 0),               -- Data. Width is constrained when the procedure is called.
  empty (log2ceil(c_DATA_WIDTH / 8) - 1 downto 0) -- Number of symbols that are empty (not valid).
  );

  subtype  t_axis_if is t_axistream_if(
      tdata  (c_DATA_WIDTH - 1 downto 0),     -- Data. Width is constrained when the procedure is called
      tkeep  (c_DATA_WIDTH / 8 - 1 downto 0), -- One valid-bit per data byte
      tuser  (0 downto 0),                    -- User sideband data
      tstrb (c_DATA_WIDTH / 8 - 1 downto 0),  -- Treated as sideband data by BFM: tstrb does not affect tdata
      tid   (0 downto 0),                     -- Treated as sideband data by BFM
      tdest (0 downto 0)                      -- Treated as sideband data by BFM
  );
  constant c_AV_ST_SRC_IDX : natural := 0;
  constant c_AV_ST_SNK_IDX : natural := 1;

  constant c_AXIS_SRC_IDX : natural := 2;
  constant c_AXIS_SNK_IDX : natural := 3;

  --   helpers
  function fill_array (n_bytes : natural) return t_slv_array;

end package stream_iface_tb_pkg;

package body stream_iface_tb_pkg is

  function fill_array (n_bytes : natural) return t_slv_array is

    variable v_res : t_slv_array(n_bytes - 1 downto 0)(7 downto 0);

  begin

    for i in 0 to n_bytes - 1 loop
      v_res(i) := std_logic_vector(to_unsigned((i mod 256), 8));
    end loop;

    return v_res;

  end function;

end package body stream_iface_tb_pkg;
