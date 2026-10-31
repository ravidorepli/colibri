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
  context colibri.common;

use work.packet_tb_pkg.all;

entity header_add_th is
  generic (
    g_HEADER_BYTES : natural;
    g_DATA_WIDTH   : natural
  );
end entity header_add_th;

architecture sim of header_add_th is

  signal  clk   : std_logic := '1';
  signal  reset : std_logic := '1';
  subtype t_axis_head_if is t_axistream_if(
    tdata  (g_HEADER_BYTES * 8 - 1 downto 0), -- Data. Width is constrained when the procedure is called
    tkeep  (g_HEADER_BYTES - 1  downto 0),    -- One valid-bit per data byte
    tuser  (0 downto 0),                      -- User sideband data
    tstrb (g_HEADER_BYTES - 1 downto 0),      -- Treated as sideband data by BFM: tstrb does not affect tdata
    tid   (0 downto 0),                       -- Treated as sideband data by BFM
    tdest (0 downto 0)                        -- Treated as sideband data by BFM
);

  subtype t_axis_pkt_if is t_axistream_if(
  tdata  (g_DATA_WIDTH - 1 downto 0),                                    -- Data. Width is constrained when the procedure is called
  tkeep  (g_DATA_WIDTH / 8 - 1  downto 0),                               -- One valid-bit per data byte
  tuser  (0 downto 0),                                                   -- User sideband data
  tstrb (g_DATA_WIDTH / 8 - 1 downto 0),                                 -- Treated as sideband data by BFM: tstrb does not affect tdata
  tid   (0 downto 0),                                                    -- Treated as sideband data by BFM
  tdest (0 downto 0)                                                     -- Treated as sideband data by BFM
);
  signal  snk_sop   : std_logic;                                         --! start of packet
  signal  snk_eop   : std_logic;                                         --! end of packet
  signal  snk_valid : std_logic;                                         --! packet valid
  signal  snk_ready : std_logic;                                         --! ready to receive
  signal  snk_data  : std_logic_vector(g_DATA_WIDTH - 1 downto 0);       --! data input
  signal  snk_empty : unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0); --! empty input

  signal src_sop   : std_logic;                                         --! start of packet
  signal src_eop   : std_logic;                                         --! end of packet
  signal src_valid : std_logic;                                         --! packet valid
  signal src_ready : std_logic;                                         --! ready to receive
  signal src_data  : std_logic_vector(g_DATA_WIDTH - 1 downto 0);       --! data input
  signal src_empty : unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0); --! empty input

  signal axis_src      : t_axis_pkt_if;
  signal axis_snk      : t_axis_pkt_if;
  signal axis_head_src : t_axis_head_if;

  signal header : std_logic_vector(g_HEADER_BYTES * 8 - 1 downto 0);

begin

  header <= swap_endianness(axis_head_src.tdata) when axis_head_src.tvalid = '1';

  axis_head_src.tready <= src_sop and src_ready;

  reset <= '0' after CLK_PERIOD_MAIN;

  uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine(func);

  clock_gen_avalon : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic
    map (
      GC_CLOCK_PERIOD    => CLK_PERIOD_MAIN,
      GC_CLOCK_HIGH_TIME => CLK_PERIOD_MAIN / 2,
      GC_INSTANCE_IDX    => CLK_MAIN
    )
    port
    map (
      clk => clk
    );

  tx_dut : entity colibri.header_add
    generic map (
      g_HEADER_BYTES => g_HEADER_BYTES,
      g_DATA_WIDTH   => g_DATA_WIDTH
    )
    port map (
      clk_i        => clk,
      reset_i      => reset,
      snk_sop_i    => src_sop,
      snk_eop_i    => src_eop,
      snk_valid_i  => src_valid,
      snk_ready_o  => src_ready,
      snk_data_i   => src_data,
      snk_empty_i  => src_empty,
      snk_header_i => header,
      src_sop_o    => snk_sop,
      src_eop_o    => snk_eop,
      src_valid_o  => snk_valid,
      src_ready_i  => snk_ready,
      src_data_o   => snk_data,
      src_empty_o  => snk_empty
    );

  axistream_tx_src : entity bitvis_vip_axistream.axistream_vvc
    generic map (
      -- When true: This VVC is an AXI4 Stream master. Data is output from BFM.
      -- When false: This VVC is an AXI4 Stream slave. Data is input to BFM.
      GC_VVC_IS_MASTER        => true,
      GC_DATA_WIDTH           => g_DATA_WIDTH,
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
      src_ready_i  => src_ready,
      src_valid_o  => src_valid,
      src_sop_o    => src_sop,
      src_eop_o    => src_eop,
      src_empty_o  => src_empty,
      src_data_o   => src_data
    );

  axistream_rx_snk : entity bitvis_vip_axistream.axistream_vvc
    generic map (
      -- When true: This VVC is an AXI4 Stream master. Data is output from BFM.
      -- When false: This VVC is an AXI4 Stream slave. Data is input to BFM.
      GC_VVC_IS_MASTER        => false,
      GC_DATA_WIDTH           => g_DATA_WIDTH,
      GC_INSTANCE_IDX         => AXIS_RX_IDX,
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
      snk_ready_o  => snk_ready,
      snk_valid_i  => snk_valid,
      snk_sop_i    => snk_sop,
      snk_eop_i    => snk_eop,
      snk_empty_i  => snk_empty,
      snk_data_i   => snk_data,
      src_tready_i => axis_snk.tready,
      src_tvalid_o => axis_snk.tvalid,
      src_tlast_o  => axis_snk.tlast,
      src_tkeep_o  => axis_snk.tkeep,
      src_tdata_o  => axis_snk.tdata
    );


  axistream_head_src : entity bitvis_vip_axistream.axistream_vvc
    generic map (
      -- When true: This VVC is an AXI4 Stream master. Data is output from BFM.
      -- When false: This VVC is an AXI4 Stream slave. Data is input to BFM.
      GC_VVC_IS_MASTER        => true,
      GC_DATA_WIDTH           => g_HEADER_BYTES * 8,
      GC_INSTANCE_IDX         => AXIS_ETH_HEADER_IDX,
      GC_AXISTREAM_BFM_CONFIG => c_AXISTREAM_AUX_CFG
    )
    port map (
      clk              => clk,
      axistream_vvc_if => axis_head_src
    );

end architecture sim;
