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

entity axis_to_avst_th is
  generic (
    g_AVST_ENDIANNESS : endian_t
  );
end entity axis_to_avst_th;

architecture sim of axis_to_avst_th is

  signal clk      : std_logic := '1';
  signal reset    : std_logic := '1';
  signal avst_snk : t_avst_if;
  signal axis_src : t_axis_if;

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

  dut : entity colibri.axis_to_avst
    generic map (
      g_DATA_WIDTH      => c_DATA_WIDTH,
      g_AVST_ENDIANNESS => g_AVST_ENDIANNESS
    )
    port map (
      clk_i                         => clk,
      reset_i                       => reset,
      snk_tready_o                  => axis_src.tready,
      snk_tvalid_i                  => axis_src.tvalid,
      snk_tlast_i                   => axis_src.tlast,
      snk_tkeep_i                   => axis_src.tkeep,
      snk_tdata_i                   => axis_src.tdata,
      src_ready_i                   => avst_snk.ready,
      src_valid_o                   => avst_snk.valid,
      src_sop_o                     => avst_snk.start_of_packet,
      src_eop_o                     => avst_snk.end_of_packet,
      std_logic_vector(src_empty_o) => avst_snk.empty,
      src_data_o                    => avst_snk.data
    );

  avalon_rx_snk : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic map (

      GC_VVC_IS_MASTER => false,
      GC_DATA_WIDTH    => c_DATA_WIDTH,
      GC_EMPTY_WIDTH   => log2ceil(c_DATA_WIDTH / 8),
      GC_INSTANCE_IDX  => c_AV_ST_SNK_IDX
    )
    port map (
      clk              => clk,
      avalon_st_vvc_if => avst_snk
    );

  avst_snk.channel    <= (others => '0');
  avst_snk.data_error <= (others => '0');

  axistream_tx_src : entity bitvis_vip_axistream.axistream_vvc
    generic map (
      -- When true: This VVC is an AXI4 Stream master. Data is output from BFM.
      -- When false: This VVC is an AXI4 Stream slave. Data is input to BFM.
      GC_VVC_IS_MASTER => true,
      GC_DATA_WIDTH    => c_DATA_WIDTH,
      GC_INSTANCE_IDX  => c_AXIS_SRC_IDX
    )
    port map (
      clk              => clk,
      axistream_vvc_if => axis_src
    );

end architecture sim;
