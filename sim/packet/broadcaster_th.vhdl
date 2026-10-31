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

entity broadcaster_th is
  generic (
    g_NUM_OUTPUTS : natural;
    g_DATA_WIDTH  : natural
  );
end entity broadcaster_th;

architecture sim of broadcaster_th is

  signal clk   : std_logic := '1';
  signal reset : std_logic := '1';

  subtype t_axis_pkt_if is t_axistream_if(
  tdata  (g_DATA_WIDTH - 1 downto 0),            -- Data. Width is constrained when the procedure is called
  tkeep  (g_DATA_WIDTH / 8 - 1  downto 0),       -- One valid-bit per data byte
  tuser  (log2ceil(g_NUM_OUTPUTS) - 1 downto 0), -- User sideband data
  tstrb (g_DATA_WIDTH / 8 - 1 downto 0),         -- Treated as sideband data by BFM: tstrb does not affect tdata
  tid   (0 downto 0),                            -- Treated as sideband data by BFM
  tdest (0 downto 0)                             -- Treated as sideband data by BFM
);

  signal dut_sop   : std_logic_vector(g_NUM_OUTPUTS - 1 downto 0); --! start of packet
  signal dut_eop   : std_logic_vector(g_NUM_OUTPUTS - 1 downto 0); --! end of packet
  signal dut_valid : std_logic_vector(g_NUM_OUTPUTS - 1 downto 0); --! packet valid
  signal dut_ready : std_logic_vector(g_NUM_OUTPUTS - 1 downto 0); --! ready to receive
  signal dut_data  : slv_array_t(g_NUM_OUTPUTS - 1 downto 0)
         (g_DATA_WIDTH - 1 downto 0);                              --! data input
  signal dut_empty : uns_array_t(g_NUM_OUTPUTS - 1 downto 0)
         (log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);                --! empty input

  signal gen_sop   : std_logic;                                         --! start of packet
  signal gen_eop   : std_logic;                                         --! end of packet
  signal gen_valid : std_logic;                                         --! valid packet
  signal gen_ready : std_logic;                                         --! ready backpressure
  signal gen_data  : std_logic_vector(g_DATA_WIDTH - 1 downto 0);       --! packet data output
  signal gen_empty : unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0); --! packet empty

  signal axis_src : t_axis_pkt_if;

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

  broadcaster_inst : entity colibri.broadcaster
    generic map (
      g_NUM_OUTPUTS => g_NUM_OUTPUTS,
      g_DATA_WIDTH  => g_DATA_WIDTH
    )
    port map (
      clk_i       => clk,
      reset_i     => reset,
      snk_sop_i   => gen_sop,
      snk_eop_i   => gen_eop,
      snk_valid_i => gen_valid,
      snk_ready_o => gen_ready,
      snk_data_i  => gen_data,
      snk_empty_i => gen_empty,
      src_sop_o   => dut_sop,
      src_eop_o   => dut_eop,
      src_valid_o => dut_valid,
      src_ready_i => dut_ready,
      src_data_o  => dut_data,
      src_empty_o => dut_empty
    );

  axistream_tx_src : entity bitvis_vip_axistream.axistream_vvc
    generic map (
      -- When true: This VVC is an AXI4 Stream master. Data is output from BFM.
      -- When false: This VVC is an AXI4 Stream slave. Data is input to BFM.
      GC_VVC_IS_MASTER        => true,
      GC_DATA_WIDTH           => g_DATA_WIDTH,
      GC_USER_WIDTH           => log2ceil(g_NUM_OUTPUTS),
      GC_INSTANCE_IDX         => AXIS_TX_IDX,
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
      src_ready_i  => gen_ready,
      src_valid_o  => gen_valid,
      src_sop_o    => gen_sop,
      src_eop_o    => gen_eop,
      src_empty_o  => gen_empty,
      src_data_o   => gen_data
    );


  gen_sinks : for i in 0 to g_NUM_OUTPUTS - 1 generate
    signal axis_snk : t_axis_pkt_if;
  begin

    axistream_rx_snk : entity bitvis_vip_axistream.axistream_vvc
      generic map (
        -- When true: This VVC is an AXI4 Stream master. Data is output from BFM.
        -- When false: This VVC is an AXI4 Stream slave. Data is input to BFM.
        GC_VVC_IS_MASTER        => false,
        GC_DATA_WIDTH           => g_DATA_WIDTH,
        GC_USER_WIDTH           => log2ceil(g_NUM_OUTPUTS),
        GC_INSTANCE_IDX         => AXIS_RX_IDX + i,
        GC_AXISTREAM_BFM_CONFIG => c_AXISTREAM_CFG

      )
      port map (
        clk              => clk,
        axistream_vvc_if => axis_snk
      );

    axis_conv_inst : entity colibri.avst_to_axis
      generic map (
        g_DATA_WIDTH => g_DATA_WIDTH
      )
      port map (
        clk_i        => clk,
        reset_i      => reset,
        snk_ready_o  => dut_ready(i),
        snk_valid_i  => dut_valid(i),
        snk_sop_i    => dut_sop(i),
        snk_eop_i    => dut_eop(i),
        snk_empty_i  => dut_empty(i),
        snk_data_i   => dut_data(i),
        src_tready_i => axis_snk.tready,
        src_tvalid_o => axis_snk.tvalid,
        src_tlast_o  => axis_snk.tlast,
        src_tkeep_o  => axis_snk.tkeep,
        src_tdata_o  => axis_snk.tdata
      );

  end generate gen_sinks;

end architecture sim;
