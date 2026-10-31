-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_clock_generator;

library bitvis_vip_avalon_st;

library osvvm;
  use osvvm.coveragepkg.all;

library colibri;
  context colibri.common;

library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.com_context;

library bitvis_vip_axistream;
  context bitvis_vip_axistream.vvc_context;

library bitvis_vip_avalon_st;
  context bitvis_vip_avalon_st.vvc_context;
use work.cc_misc_tb_pkg.all;

entity packet_cc_ram_fifo_th is
  generic (
    g_SNK_DATA_WIDTH : natural := 16;
    g_SRC_DATA_WIDTH : natural := 32
  );
end entity packet_cc_ram_fifo_th;

architecture sim of packet_cc_ram_fifo_th is

  subtype t_avst_snk_if is t_avalon_st_if(
  channel (0 downto 0),                               -- Channel number for data being transferred on the current cycle.
  data_error(0 downto 0),
  data (g_SNK_DATA_WIDTH - 1 downto 0),               -- Data. Width is constrained when the procedure is called.
  empty (log2ceil(g_SNK_DATA_WIDTH / 8) - 1 downto 0) -- Number of symbols that are empty (not valid).
  );

  subtype t_avst_src_if is t_avalon_st_if(
  channel (0 downto 0),                               -- Channel number for data being transferred on the current cycle.
  data_error(0 downto 0),
  data (g_SRC_DATA_WIDTH - 1 downto 0),               -- Data. Width is constrained when the procedure is called.
  empty (log2ceil(g_SRC_DATA_WIDTH / 8) - 1 downto 0) -- Number of symbols that are empty (not valid).
  );

  signal wrclk : std_logic := '1';
  signal rdclk : std_logic := '1';
  signal reset : std_logic := '1';

  --
  signal av_snk : t_avst_snk_if;
  signal av_src : t_avst_src_if;

  signal wrfull  : std_logic;
  signal wrempty : std_logic;
  signal rdfull  : std_logic;
  signal rdempty : std_logic;

  signal size : unsigned (log2ceil(c_MAX_PACKET_BYTES * c_NUM_PACKETS) - 1 downto 0);

  subtype t_axis_if is t_axistream_if(
    tdata  (7 downto 0),  -- Data. Width is constrained when the procedure is called
    tkeep  (0  downto 0), -- One valid-bit per data byte
    tuser  (0 downto 0),  -- User sideband data
    tstrb (0 downto 0),   -- Treated as sideband data by BFM: tstrb does not affect tdata
    tid   (0 downto 0),   -- Treated as sideband data by BFM
    tdest (0 downto 0)    -- Treated as sideband data by BFM
    );

  signal axis_side_snk                                                   : t_axis_if;
  -- OSSVM vars
  shared variable v_bin1, v_bin2, v_bin3, v_bin4, v_bin5, v_bin6, v_bin7 : covptype;

begin

  reset <= '0' after 5 * c_CLK_PERIOD_40;

  proc_coverage : process is
  begin

    --- OSVVM SETUP ---
    -- Set up coverage v_bins
    v_bin1.AddBins("Write while empty", 2, ONE_BIN);
    v_bin2.AddBins("Read while full", 2, ONE_BIN);
    v_bin3.AddBins("Read and write ", ONE_BIN);
    v_bin4.AddBins("Read without write", ONE_BIN);
    v_bin5.AddBins("Write without read", ONE_BIN);
    v_bin6.AddBins("Write while full", ONE_BIN);
    v_bin7.AddBins("Read while empty", ONE_BIN);

    loop
      wait for c_CLK_PERIOD_40;

      -- Collect coverage data
      v_bin1.ICover(to_integer(av_src.valid = '1' and wrempty = '1'));
      v_bin2.ICover(to_integer(av_snk.ready = '1' and rdfull = '1'));
      v_bin3.ICover(to_integer(av_snk.ready = '1' and av_src.valid = '1' and rdempty = '0' and wrfull = '0'));
      v_bin4.ICover(to_integer(av_snk.ready = '1' and av_src.valid = '0' and rdempty = '0'));
      v_bin5.ICover(to_integer(av_snk.ready = '0' and av_src.valid = '1' and wrfull = '0'));
      v_bin6.ICover(to_integer(av_src.valid = '1' and wrfull = '1'));
      v_bin7.ICover(to_integer(av_snk.ready = '1' and rdempty = '1'));
      -- Stop the test when all coverage goals have been met
      exit when
      v_bin1.IsCovered and
      v_bin2.IsCovered and
      v_bin3.IsCovered and
      v_bin4.IsCovered and
      v_bin5.IsCovered and
      v_bin6.IsCovered and
      v_bin7.IsCovered
;
    end loop;

    info("Coverage goals met!");
    wait;

  end process proc_coverage;

  proc_print_cov : process is

    variable v_act : actor_t := new_actor("print_coverage");
    variable msg   : msg_t;

  begin

    receive(net, v_act, msg);
    -- Print coverage data
    v_bin1.WriteBin;
    v_bin2.WriteBin;
    v_bin3.WriteBin;
    v_bin4.WriteBin;
    v_bin5.WriteBin;
    v_bin6.WriteBin;
    v_bin7.WriteBin;

    wait;

  end process proc_print_cov;

  uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine(func);

  clock40_gen : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic map (

      GC_CLOCK_PERIOD    => c_CLK_PERIOD_40,
      GC_CLOCK_HIGH_TIME => c_CLK_PERIOD_40 / 2,
      GC_INSTANCE_IDX    => c_CLK_40
    )
    port map (
      clk => wrclk
    );

  clock60_gen : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic map (

      GC_CLOCK_PERIOD    => c_CLK_PERIOD_60,
      GC_CLOCK_HIGH_TIME => c_CLK_PERIOD_60 / 2,
      GC_INSTANCE_IDX    => c_CLK_60
    )
    port map (
      clk => rdclk
    );

  dut : entity colibri.packet_cc_ram_fifo(rtl)
    generic map (

      g_MAX_PACKET_BYTES => c_MAX_PACKET_BYTES,
      g_NUM_PACKETS      => c_NUM_PACKETS,
      g_SNK_DATA_WIDTH   => g_SRC_DATA_WIDTH,
      g_SRC_DATA_WIDTH   => g_SNK_DATA_WIDTH
    )
    port map (
      snk_clk_i                     => wrclk,
      reset_i                       => reset,
      src_clk_i                     => rdclk,
      snk_ready_o                   => av_src.ready,
      snk_valid_i                   => av_src.valid,
      snk_sop_i                     => av_src.start_of_packet,
      snk_eop_i                     => av_src.end_of_packet,
      snk_empty_i                   => unsigned(av_src.empty),
      snk_data_i                    => av_src.data,
      snk_drop_i                    => av_src.channel(0),
      src_ready_i                   => av_snk.ready,
      src_valid_o                   => av_snk.valid,
      src_sop_o                     => av_snk.start_of_packet,
      src_eop_o                     => av_snk.end_of_packet,
      std_logic_vector(src_empty_o) => av_snk.empty,
      src_data_o                    => av_snk.data,
      src_size_o                    => size
    );
  av_snk.channel <= "0";

  avalon_tx_src : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic map (

      GC_VVC_IS_MASTER        => true,
      GC_DATA_WIDTH           => g_SRC_DATA_WIDTH,
      GC_EMPTY_WIDTH          => log2ceil(g_SRC_DATA_WIDTH / 8),
      GC_INSTANCE_IDX         => c_AV_ST_SRC_IDX,
      GC_AVALON_ST_BFM_CONFIG => c_AVST_BFM_CONF
    )
    port map (
      clk              => wrclk,
      avalon_st_vvc_if => av_src
    );

  avalon_rx_snk : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic map (

      GC_VVC_IS_MASTER        => false,
      GC_DATA_WIDTH           => g_SNK_DATA_WIDTH,
      GC_EMPTY_WIDTH          => log2ceil(g_SNK_DATA_WIDTH  / 8),
      GC_INSTANCE_IDX         => c_AV_ST_SNK_IDX,
      GC_AVALON_ST_BFM_CONFIG => c_AVST_BFM_CONF
    )
    port map (
      clk              => rdclk,
      avalon_st_vvc_if => av_snk
    );

  axistream_head_src : entity bitvis_vip_axistream.axistream_vvc
    generic map (
      -- When true: This VVC is an AXI4 Stream master. Data is output from BFM.
      -- When false: This VVC is an AXI4 Stream slave. Data is input to BFM.
      GC_VVC_IS_MASTER        => false,
      GC_DATA_WIDTH           => 8,
      GC_INSTANCE_IDX         => c_AXIS_SIDE_IDX,
      GC_AXISTREAM_BFM_CONFIG => c_AXISTREAM_CFG

    )
    port map (
      clk              => rdclk,
      axistream_vvc_if => axis_side_snk
    );

  axis_side_snk.tdata  <= std_logic_vector(resize(size, 8));
  axis_side_snk.tvalid <= av_snk.start_of_packet and av_snk.valid and av_snk.ready;
  axis_side_snk.tlast  <= av_snk.start_of_packet and av_snk.valid and av_snk.ready;
  axis_side_snk.tkeep  <= (others => '1');

end architecture sim;
