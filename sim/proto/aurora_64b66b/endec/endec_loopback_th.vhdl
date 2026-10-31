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
  use colibri.aurora_const.all;

use work.endec_loopback_pkg.all;

entity endec_loopback_th is
end entity endec_loopback_th;

architecture sim of endec_loopback_th is

  signal av_clk           : std_logic := '1';
  signal reset            : std_logic := '1';
  signal aurora_data      : slv_array_t(N_LANES - 1 downto 0)(c_AURORA_ENC_WIDTH - 1 downto 0);
  signal aurora_ready_vec : std_logic_vector(N_LANES - 1 downto 0);
  signal aurora_valid_vec : std_logic_vector(N_LANES - 1 downto 0);
  signal aurora_ready     : std_logic;
  signal aurora_valid     : std_logic;
  signal aurora_link_up   : std_logic := '1';
  --
  signal av_encode        : t_avst_if;
  signal av_decode        : t_avst_if;

begin

  reset <= '0' after CLK_PERIOD_LANE;

  uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine(func);

  clock_gen_avalon : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic
    map (
      GC_CLOCK_PERIOD    => CLK_PERIOD_AVALON,
      GC_CLOCK_HIGH_TIME => CLK_PERIOD_AVALON / 2,
      GC_INSTANCE_IDX    => CLK_AVALON
    )
    port map (
      clk => av_clk
    );

  av_decode.channel <= "0";

  decoder_dut : entity colibri.aurora_st_decoder(rtl)
    generic
    map (
      g_N_LANES        => N_LANES
    )
    port
    map (
      clk_i                         => av_clk,
      reset_i                       => reset,
      snk_data_i                    => aurora_data,
      snk_valid_i                   => aurora_valid,
      snk_ready_o                   => aurora_ready,
      snk_link_up_i                 => aurora_link_up,
      src_sop_o                     => av_decode.start_of_packet,
      src_eop_o                     => av_decode.end_of_packet,
      src_valid_o                   => av_decode.valid,
      src_error_o                   => av_decode.data_error(0),
      src_data_o                    => av_decode.data,
      std_logic_vector(src_empty_o) => av_decode.empty
    );

  gen_ready : for i in 0 to N_LANES - 1 generate
    aurora_ready_vec(i) <= aurora_ready;

  end generate gen_ready;

  aurora_valid <= and aurora_valid_vec;

  encoder_dut : entity colibri.aurora_st_encoder(rtl)
    generic
    map (
      g_N_LANES        => N_LANES
    )
    port
    map (
      clk_i       => av_clk,
      reset_i     => reset,
      snk_sop_i   => av_encode.start_of_packet,
      snk_eop_i   => av_encode.end_of_packet,
      snk_valid_i => av_encode.valid,
      snk_ready_o => av_encode.ready,
      snk_data_i  => av_encode.data,
      snk_empty_i => unsigned(av_encode.empty),
      src_data_o  => aurora_data,
      src_valid_o => aurora_valid_vec,
      src_ready_i => aurora_ready_vec
    );

  avalon_en_src : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic
    map (
      GC_VVC_IS_MASTER => true,
      GC_DATA_WIDTH    => c_AURORA_DATA_WIDTH,
      GC_EMPTY_WIDTH   => log2ceil(c_AURORA_DATA_WIDTH / 8),
      GC_INSTANCE_IDX  => ENCODE_IDX
    )
    port
    map (
      clk              => av_clk,
      avalon_st_vvc_if => av_encode
    );

  avalon_de_snk : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic
    map (
      GC_VVC_IS_MASTER => false,
      GC_DATA_WIDTH    => c_AURORA_DATA_WIDTH,
      GC_EMPTY_WIDTH   => log2ceil(c_AURORA_DATA_WIDTH / 8),
      GC_INSTANCE_IDX  => DECODE_IDX
    )
    port
    map (
      clk              => av_clk,
      avalon_st_vvc_if => av_decode
    );

end architecture sim;
