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

library bitvis_vip_axistream;

library colibri;
  context colibri.common;

use work.stream_iface_tb_pkg.all;

entity avst_to_axis_th is
  generic (
    g_AVST_ENDIANNESS : endian_t
  );
end entity avst_to_axis_th;

architecture sim of avst_to_axis_th is

  signal clk      : std_logic := '1';
  signal reset    : std_logic := '1';
  signal avst_src : t_avst_if;
  signal axis_snk : t_axis_if;

begin

  reset <= '0' after c_CLK_PERIOD_40;

  uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine(func);

  clock_gen : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic map (

      GC_CLOCK_PERIOD    => c_CLK_PERIOD_40,
      GC_CLOCK_HIGH_TIME => c_CLK_PERIOD_40 / 2,
      GC_INSTANCE_IDX    => c_CLK_40
    )
    port map (
      clk => clk
    );

  dut : entity colibri.avst_to_axis
    generic map (
      g_DATA_WIDTH      => c_DATA_WIDTH,
      g_AVST_ENDIANNESS => g_AVST_ENDIANNESS
    )
    port map (
      clk_i        => clk,
      reset_i      => reset,
      snk_ready_o  => avst_src.ready,
      snk_valid_i  => avst_src.valid,
      snk_sop_i    => avst_src.start_of_packet,
      snk_eop_i    => avst_src.end_of_packet,
      snk_empty_i  => unsigned(avst_src.empty),
      snk_data_i   => avst_src.data,
      src_tready_i => axis_snk.tready,
      src_tvalid_o => axis_snk.tvalid,
      src_tlast_o  => axis_snk.tlast,
      src_tkeep_o  => axis_snk.tkeep,
      src_tdata_o  => axis_snk.tdata
    );

  avalon_tx_src : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic map (

      GC_VVC_IS_MASTER => true,
      GC_DATA_WIDTH    => c_DATA_WIDTH,
      GC_EMPTY_WIDTH   => log2ceil(c_DATA_WIDTH / 8),
      GC_INSTANCE_IDX  => c_AV_ST_SRC_IDX
    )
    port map (
      clk              => clk,
      avalon_st_vvc_if => avst_src
    );

  axistream_rx_snk : entity bitvis_vip_axistream.axistream_vvc
    generic map (
      -- When true: This VVC is an AXI4 Stream master. Data is output from BFM.
      -- When false: This VVC is an AXI4 Stream slave. Data is input to BFM.
      GC_VVC_IS_MASTER => false,
      GC_DATA_WIDTH    => c_DATA_WIDTH,
      GC_INSTANCE_IDX  => c_AXIS_SNK_IDX
    )
    port map (
      clk              => clk,
      axistream_vvc_if => axis_snk
    );

end architecture sim;
