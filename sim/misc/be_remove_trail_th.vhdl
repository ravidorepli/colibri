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

library colibri;
  context colibri.common;
  use work.misc_tb_pkg.all;

entity be_remove_trail_th is
end entity be_remove_trail_th;

architecture sim of be_remove_trail_th is

  signal   clk        : std_logic                := '1';
  signal   reset      : std_logic                := '1';
  constant c_HEAD_SIG :
   unsigned(log2ceil(c_DATA_WIDTH / 8) downto 0) :=
                                                    to_unsigned(c_HEADER_SIZE, log2ceil(c_DATA_WIDTH / 8) + 1);
  signal   av_snk     : t_avst_if;
  signal   av_src     : t_avst_if;

begin

  reset <= '0' after c_CLK_PERIOD_40;

  uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine(func);

  clock_gen : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic
    map (
      GC_CLOCK_PERIOD    => c_CLK_PERIOD_40,
      GC_CLOCK_HIGH_TIME => c_CLK_PERIOD_40 / 2,
      GC_INSTANCE_IDX    => c_CLK_40
    )
    port map (
      clk => clk
    );

  avalon_tx_src : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic
    map (
      GC_VVC_IS_MASTER => true,
      GC_DATA_WIDTH    => c_DATA_WIDTH,
      GC_EMPTY_WIDTH   => log2ceil(c_DATA_WIDTH / 8),
      GC_INSTANCE_IDX  => c_AV_ST_SRC_IDX
    )
    port
    map (
      clk              => clk,
      avalon_st_vvc_if => av_src
    );

  avalon_rx_snk : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic
    map (
      GC_VVC_IS_MASTER => false,
      GC_DATA_WIDTH    => c_DATA_WIDTH,
      GC_EMPTY_WIDTH   => log2ceil(c_DATA_WIDTH / 8),
      GC_INSTANCE_IDX  => c_AV_ST_SNK_IDX
    )
    port
    map (
      clk              => clk,
      avalon_st_vvc_if => av_snk
    );

  dut : entity colibri.be_remove_trail(rtl)
    generic
    map (

      g_DATA_WIDTH   => c_DATA_WIDTH,
      g_REGISTER_OUT => false
    )
    port
    map (
      clk_i                         => clk,
      reset_i                       => reset,
      shl_i                         => c_HEAD_SIG,
      snk_ready_o                   => av_src.ready,
      snk_valid_i                   => av_src.valid,
      snk_sop_i                     => av_src.start_of_packet,
      snk_eop_i                     => av_src.end_of_packet,
      snk_empty_i                   => unsigned(av_src.empty),
      snk_data_i                    => av_src.data,
      src_ready_i                   => av_snk.ready,
      src_valid_o                   => av_snk.valid,
      src_sop_o                     => av_snk.start_of_packet,
      src_eop_o                     => av_snk.end_of_packet,
      std_logic_vector(src_empty_o) => av_snk.empty,
      src_data_o                    => av_snk.data,
      src_tail_o                    => open
    );

  av_snk.channel <= "0";

end architecture sim;
