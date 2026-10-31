-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  context colibri.common;
  use colibri.poly.all;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_clock_generator;

library bitvis_vip_avalon_st;
  context bitvis_vip_avalon_st.vvc_context;

library bitvis_vip_axistream;
  context bitvis_vip_axistream.vvc_context;

--
library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;

use work.comms_tb_pkg.all;

entity crc_th is
  generic (
    g_DATA_WIDTH : positive         := 32;
    g_CRC_POLY   : std_logic_vector;
    g_INIT_VAL   : std_logic_vector := (g_CRC_POLY'range => '0');
    g_INVERT_IN  : boolean          := false;
    g_INVERT_OUT : boolean          := false;
    g_XOR_OUT    : std_logic_vector := (g_CRC_POLY'range => '0')
  );
end entity crc_th;

architecture bench of crc_th is

  -- Clock period
  constant c_CLK_PERIOD : time := 5 ns;
  -- Generics

  subtype t_avst_if is t_avalon_st_if(
  channel (0 downto 0),                           -- Channel number for data being transferred on the current cycle.
  data_error(0 downto 0),
  data (g_DATA_WIDTH - 1 downto 0),               -- Data. Width is constrained when the procedure is called.
  empty (log2ceil(g_DATA_WIDTH / 8) - 1 downto 0) -- Number of symbols that are empty (not valid).
  );

  subtype t_axis_if is t_axistream_if(
  tdata  (g_CRC_POLY'length - 1 downto 0),      -- Data. Width is constrained when the procedure is called
  tkeep  (g_CRC_POLY'length / 8 - 1  downto 0), -- One valid-bit per data byte
  tuser  (0 downto 0),                          -- User sideband data
  tstrb (g_CRC_POLY'length / 8 - 1 downto 0),   -- Treated as sideband data by BFM: tstrb does not affect tdata
  tid   (0 downto 0),                           -- Treated as sideband data by BFM
  tdest (0 downto 0)                            -- Treated as sideband data by BFM
);

  -- Ports
  signal clk   : std_logic := '1';
  signal reset : std_logic := '1';

  signal av_snk : t_avst_if;
  signal av_src : t_avst_if;

  signal axis_crc_snk : t_axis_if;
  signal src_crc      : std_logic_vector(g_CRC_POLY'length - 1 downto 0);

begin

  reset <= '0' after c_CLK_PERIOD;

  uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine(func);

  dut_inst : entity colibri.crc
    generic map (
      g_DATA_WIDTH => g_DATA_WIDTH,
      g_CRC_POLY   => g_CRC_POLY,
      g_INIT_VAL   => g_INIT_VAL,
      g_INVERT_IN  => g_INVERT_IN,
      g_INVERT_OUT => g_INVERT_OUT,
      g_XOR_OUT    => g_XOR_OUT
    )
    port map (
      clk_i                         => clk,
      reset_i                       => reset,
      snk_data_i                    => av_src.data,
      snk_sop_i                     => av_src.start_of_packet,
      snk_eop_i                     => av_src.end_of_packet,
      snk_empty_i                   => unsigned(av_src.empty),
      snk_valid_i                   => av_src.valid,
      snk_ready_o                   => av_src.ready,
      src_data_o                    => av_snk.data,
      src_sop_o                     => av_snk.start_of_packet,
      src_eop_o                     => av_snk.end_of_packet,
      std_logic_vector(src_empty_o) => av_snk.empty,
      src_valid_o                   => av_snk.valid,
      src_ready_i                   => av_snk.ready,
      src_crc_o                     => src_crc
    );

  clock_gen : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic map (

      GC_CLOCK_PERIOD    => c_CLK_PERIOD,
      GC_CLOCK_HIGH_TIME => c_CLK_PERIOD / 2,
      GC_INSTANCE_IDX    => c_CLK_GEN
    )
    port map (
      clk => clk
    );

  avalon_tx_src : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic map (

      GC_VVC_IS_MASTER        => true,
      GC_DATA_WIDTH           => g_DATA_WIDTH,
      GC_EMPTY_WIDTH          => log2ceil(g_DATA_WIDTH / 8),
      GC_INSTANCE_IDX         => c_AV_ST_SRC_IDX,
      GC_AVALON_ST_BFM_CONFIG => c_AVST_CONFIG
    )
    port map (
      clk              => clk,
      avalon_st_vvc_if => av_src
    );

  avalon_rx_snk : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic map (

      GC_VVC_IS_MASTER        => false,
      GC_DATA_WIDTH           => g_DATA_WIDTH,
      GC_EMPTY_WIDTH          => log2ceil(g_DATA_WIDTH / 8),
      GC_INSTANCE_IDX         => c_AV_ST_SNK_IDX,
      GC_AVALON_ST_BFM_CONFIG => c_AVST_CONFIG
    )
    port map (
      clk              => clk,
      avalon_st_vvc_if => av_snk
    );

  av_snk.channel <= "0";

  axistream_crc_src : entity bitvis_vip_axistream.axistream_vvc
    generic map (
      GC_VVC_IS_MASTER        => false,
      GC_DATA_WIDTH           => g_CRC_POLY'length,
      GC_INSTANCE_IDX         => c_AXIS_CRC_IDX,
      GC_AXISTREAM_BFM_CONFIG => c_AXISTREAM_CFG
    )
    port map (
      clk              => clk,
      axistream_vvc_if => axis_crc_snk
    );

  axis_crc_snk.tdata  <= swap_endianness(src_crc);
  axis_crc_snk.tvalid <= av_snk.end_of_packet and av_snk.valid and av_snk.ready;
  axis_crc_snk.tkeep  <= (others => '1');

end architecture bench;
