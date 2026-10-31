-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  context colibri.common;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_clock_generator;

library bitvis_vip_avalon_st;

library bitvis_vip_wishbone;
use work.mmap_fifo_sim_pkg.all;

entity mmap_fifo_th is
  port (
    intr_o : out   std_logic
  );
end entity mmap_fifo_th;

architecture bench of mmap_fifo_th is

  -- Ports
  signal reset  : std_logic := '1';
  signal clk    : std_logic := '1';
  signal wb_clk : std_logic := '1';

  signal av_s2mm : t_avst_if;
  signal avm_vvc : t_avst_if;
  signal av_mm2s : t_avst_if;
  signal wbm     : t_wbm_if;

  signal txintr, rxintr : std_logic;

begin

  reset <= '0' after c_CLK_PERIOD;

  uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine(func);

  clock_gen : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic map (

      GC_CLOCK_PERIOD    => c_CLK_PERIOD,
      GC_CLOCK_HIGH_TIME => c_CLK_PERIOD / 2,
      GC_INSTANCE_IDX    => c_CLK_MAIN
    )
    port map (
      clk => clk
    );

  wbclock_gen : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic map (

      GC_CLOCK_PERIOD    => c_WB_CLK_PERIOD,
      GC_CLOCK_HIGH_TIME => c_WB_CLK_PERIOD / 2,
      GC_INSTANCE_IDX    => c_CLK_WB
    )
    port map (
      clk => wb_clk
    );

  dut_inst : entity colibri.mmap_fifo
    generic map (
      g_WB_ADDR_WIDTH     => c_WB_ADDR_WIDTH,
      g_WB_DATA_WIDTH     => c_WB_DATA_WIDTH,
      g_STREAM_DATA_WIDTH => c_STREAM_DATA_WIDTH,
      g_NUM_WORDS         => c_NUM_WORDS,
      g_NUM_CH            => c_NUM_CH
    )
    port map (
      reset_i  => reset,
      clk_i    => clk,
      wb_clk_i => wb_clk,
      --
      snk_ready_o => av_s2mm.ready,
      snk_valid_i => av_s2mm.valid,
      snk_sop_i   => av_s2mm.start_of_packet,
      snk_eop_i   => av_s2mm.end_of_packet,
      snk_empty_i => unsigned(av_s2mm.empty),
      snk_data_i  => av_s2mm.data,
      snk_chan_i  => unsigned(av_s2mm.channel),
      --
      src_ready_i                   => av_mm2s.ready,
      src_valid_o                   => av_mm2s.valid,
      src_sop_o                     => av_mm2s.start_of_packet,
      src_eop_o                     => av_mm2s.end_of_packet,
      std_logic_vector(src_empty_o) => av_mm2s.empty,
      src_data_o                    => av_mm2s.data,
      std_logic_vector(src_chan_o)  => av_mm2s.channel,
      --
      wb_adr_i  => unsigned(wbm.adr_o),
      wb_dat_o  => wbm.dat_i,
      wb_dat_i  => wbm.dat_o,
      wb_we_i   => wbm.we_o,
      wb_sel_i  => (others => '1'),
      wb_stb_i  => wbm.stb_o,
      wb_cyc_i  => wbm.cyc_o,
      wb_ack_o  => wbm.ack_i,
      wb_err_o  => open,
      tx_intr_o => txintr,
      rx_intr_o => rxintr
    );

  intr_o <= txintr or rxintr;

  wbm_inst : entity bitvis_vip_wishbone.wishbone_vvc
    generic map (
      GC_ADDR_WIDTH          => c_WB_ADDR_WIDTH,
      GC_DATA_WIDTH          => c_WB_DATA_WIDTH,
      GC_INSTANCE_IDX        => c_WBM,
      GC_WISHBONE_BFM_CONFIG => c_WBM_CONFIG
    )
    port map (
      clk                    => wb_clk,
      wishbone_vvc_master_if => wbm
    );

  avalon_s2mm_src : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic map (

      GC_VVC_IS_MASTER        => true,
      GC_DATA_WIDTH           => c_STREAM_DATA_WIDTH,
      GC_EMPTY_WIDTH          => log2ceil(c_STREAM_DATA_WIDTH / 8),
      GC_CHANNEL_WIDTH        => log2ceil(c_NUM_CH),
      GC_INSTANCE_IDX         => c_AVST_S2MM,
      GC_AVALON_ST_BFM_CONFIG => c_AVST_CONFIG
    )
    port map (
      clk              => clk,
      avalon_st_vvc_if => av_s2mm
    );


  avalon_mm2s : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic map (

      GC_VVC_IS_MASTER        => false,
      GC_DATA_WIDTH           => c_STREAM_DATA_WIDTH,
      GC_EMPTY_WIDTH          => log2ceil(c_STREAM_DATA_WIDTH / 8),
      GC_CHANNEL_WIDTH        => log2ceil(c_NUM_CH),
      GC_INSTANCE_IDX         => c_AVST_MM2S,
      GC_AVALON_ST_BFM_CONFIG => c_AVST_CONFIG
    )
    port map (
      clk              => clk,
      avalon_st_vvc_if => av_mm2s
    );

end architecture bench;
