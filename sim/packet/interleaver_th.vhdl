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

library bitvis_vip_axistream;
  context bitvis_vip_axistream.vvc_context;

library colibri;
  use colibri.types.all;
  context colibri.common;

use work.packet_tb_pkg.all;

entity interleaver_th is
  generic (
    g_NUM_INPUTS : natural;
    g_DATA_WIDTH : natural;
    g_INTERLEAVE_WORDS : boolean := true

  );
end entity interleaver_th;

architecture sim of interleaver_th is

  signal clk   : std_logic := '1';
  signal reset : std_logic := '1';

  subtype t_axis_pkt_if is t_axistream_if(
  tdata  (g_DATA_WIDTH - 1 downto 0),           -- Data. Width is constrained when the procedure is called
  tkeep  (g_DATA_WIDTH / 8 - 1  downto 0),      -- One valid-bit per data byte
  tuser  (log2ceil(g_NUM_INPUTS) - 1 downto 0), -- User sideband data
  tstrb (g_DATA_WIDTH / 8 - 1 downto 0),        -- Treated as sideband data by BFM: tstrb does not affect tdata
  tid   (0 downto 0),                           -- Treated as sideband data by BFM
  tdest (0 downto 0)                            -- Treated as sideband data by BFM
);

  signal gen_sop   : std_logic_vector(g_NUM_INPUTS - 1 downto 0); --! start of packet
  signal gen_eop   : std_logic_vector(g_NUM_INPUTS - 1 downto 0); --! end of packet
  signal gen_valid : std_logic_vector(g_NUM_INPUTS - 1 downto 0); --! packet valid
  signal gen_ready : std_logic_vector(g_NUM_INPUTS - 1 downto 0); --! ready to receive
  signal gen_data  : slv_array_t(g_NUM_INPUTS - 1 downto 0)
         (g_DATA_WIDTH - 1 downto 0);                             --! data input
  signal gen_empty : uns_array_t(g_NUM_INPUTS - 1 downto 0)
         (log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);               --! empty input

  signal dut_sop      : std_logic;                                         --! start of packet
  signal dut_eop      : std_logic;                                         --! end of packet
  signal dut_valid    : std_logic;                                         --! valid packet
  signal dut_ready    : std_logic;                                         --! ready backpressure
  signal dut_data     : std_logic_vector(g_DATA_WIDTH - 1 downto 0);       --! packet data output
  signal dut_empty    : unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0); --! packet empty
  signal dut_channel  : unsigned(log2ceil(g_NUM_INPUTS) - 1 downto 0);     --! input channel
  signal axis_data_ch : std_logic_vector(dut_data'length + dut_channel'length -1 downto 0);

  signal axis_main_snk  : t_axis_pkt_if;
  signal axis_ready_all : std_logic_vector(g_NUM_INPUTS - 1 downto 0);

begin

  reset <= '0' after CLK_PERIOD_MAIN;

  uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine(func);

  clock_gen_avalon : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic map (

      GC_CLOCK_PERIOD    => CLK_PERIOD_MAIN,
      GC_CLOCK_HIGH_TIME => CLK_PERIOD_MAIN / 2,
      GC_INSTANCE_IDX    => CLK_MAIN
    )
    port map (
      clk => clk
    );

  interleaver_inst : entity colibri.interleaver
    generic map (
      g_NUM_INPUTS => g_NUM_INPUTS,
      g_DATA_WIDTH => g_DATA_WIDTH,
    g_INTERLEAVE_WORDS  => g_INTERLEAVE_WORDS
    )
    port map (
      clk_i         => clk,
      reset_i       => reset,
      snk_sop_i     => gen_sop,
      snk_eop_i     => gen_eop,
      snk_valid_i   => gen_valid,
      snk_ready_o   => gen_ready,
      snk_data_i    => gen_data,
      snk_empty_i   => gen_empty,
      src_sop_o     => dut_sop,
      src_eop_o     => dut_eop,
      src_valid_o   => dut_valid,
      src_ready_i   => dut_ready,
      src_data_o    => dut_data,
      src_empty_o   => dut_empty,
      src_channel_o => dut_channel
    );

  gen_sources : for i in 0 to g_NUM_INPUTS - 1 generate
    signal axis_src : t_axis_pkt_if;
  begin

    axistream_tx_src : entity bitvis_vip_axistream.axistream_vvc
      generic map (
        -- When true: This VVC is an AXI4 Stream master. Data is output from BFM.
        -- When false: This VVC is an AXI4 Stream slave. Data is input to BFM.
        GC_VVC_IS_MASTER        => true,
        GC_DATA_WIDTH           => g_DATA_WIDTH,
        GC_USER_WIDTH           => log2ceil(g_NUM_INPUTS),
        GC_INSTANCE_IDX         => AXIS_TX_IDX + i,
        GC_AXISTREAM_BFM_CONFIG => c_AXISTREAM_CFG

      )
      port map (
        clk              => clk,
        axistream_vvc_if => axis_src
      );

    avst_conv_inst : entity colibri.axis_to_avst
      generic map (
        g_DATA_WIDTH => g_DATA_WIDTH
      )
      port map (
        clk_i        => clk,
        reset_i      => reset,
        snk_tready_o => axis_src.tready,
        snk_tvalid_i => axis_src.tvalid,
        snk_tlast_i  => axis_src.tlast,
        snk_tkeep_i  => axis_src.tkeep,
        snk_tdata_i  => axis_src.tdata,
        src_ready_i  => gen_ready(i),
        src_valid_o  => gen_valid(i),
        src_sop_o    => gen_sop(i),
        src_eop_o    => gen_eop(i),
        src_empty_o  => gen_empty(i),
        src_data_o   => gen_data(i)
      );

  end generate gen_sources;

  axis_conv_inst : entity colibri.avst_to_axis
    generic map (
      g_DATA_WIDTH => g_DATA_WIDTH
    )
    port map (
      clk_i        => clk,
      reset_i      => reset,
      snk_ready_o  => dut_ready,
      snk_valid_i  => dut_valid,
      snk_sop_i    => dut_sop,
      snk_eop_i    => dut_eop,
      snk_empty_i  => dut_empty,
      snk_data_i   => dut_data,
      src_tready_i => axis_main_snk.tready,
      src_tvalid_o => axis_main_snk.tvalid,
      src_tlast_o  => axis_main_snk.tlast,
      src_tkeep_o  => axis_main_snk.tkeep,
      src_tdata_o  => axis_main_snk.tdata
    );

  axis_main_snk.tready <= and(axis_ready_all);

  gen_sinks : for i in 0 to g_NUM_INPUTS - 1 generate
    signal axis_snk : t_axis_pkt_if;
  begin

    axistream_rx_snk : entity bitvis_vip_axistream.axistream_vvc
      generic map (
        -- When true: This VVC is an AXI4 Stream master. Data is output from BFM.
        -- When false: This VVC is an AXI4 Stream slave. Data is input to BFM.
        GC_VVC_IS_MASTER        => false,
        GC_DATA_WIDTH           => g_DATA_WIDTH,
        GC_USER_WIDTH           => log2ceil(g_NUM_INPUTS),
        GC_INSTANCE_IDX         => AXIS_RX_IDX + i,
        GC_AXISTREAM_BFM_CONFIG => c_AXISTREAM_CFG

      )
      port map (
        clk              => clk,
        axistream_vvc_if => axis_snk
      );

    axis_ready_all(i) <= axis_snk.tready;

    proc_mux_sinks : process (all) is
    begin

      if (dut_channel = i) then
        axis_snk.tvalid <= axis_main_snk.tvalid and axis_snk.tready;
        axis_snk.tlast  <= axis_main_snk.tlast;
        axis_snk.tkeep  <= axis_main_snk.tkeep;
        axis_snk.tdata  <= axis_main_snk.tdata;
        axis_snk.tuser  <= std_logic_vector(dut_channel);
      else
        axis_snk.tvalid <= '0';
        axis_snk.tlast  <= '0';
        axis_snk.tkeep  <= (others => '0');
        axis_snk.tdata  <= (others => '0');
      end if;

    end process proc_mux_sinks;

  end generate gen_sinks;

end architecture sim;
