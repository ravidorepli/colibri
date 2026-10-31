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

use work.aurora_loopback_pkg.all;

entity aurora_loopback_th is
  generic (
    g_DELAY_LANE   : boolean := false;
    g_ERROR_INJECT : boolean := false;
    g_NUM_LANES      : natural := 4;
    g_LANE_WIDTH   : natural := 16
  );
end entity aurora_loopback_th;

architecture sim of aurora_loopback_th is

  signal av_clk    : std_logic := '1';
  signal elink_clk : std_logic := '1';
  signal reset_tx  : std_logic := '1';
  signal reset_rx  : std_logic := '1';

  signal aurora_data_tx  : slv_array_t(g_NUM_LANES - 1 downto 0)(g_LANE_WIDTH - 1 downto 0);
  signal aurora_data_rx  : slv_array_t(g_NUM_LANES - 1 downto 0)(g_LANE_WIDTH - 1 downto 0);
  signal aurora_valid_tx : std_logic_vector(g_NUM_LANES - 1 downto 0) := (others => '1');
  signal aurora_valid_rx : std_logic_vector(g_NUM_LANES - 1 downto 0) := (others => '1');
  signal aurora_link_up  : std_logic                              := '1';
  --
  signal av_tx           : t_avst_if;
  signal av_rx           : t_avst_if;

begin

  reset_tx <= '0' after CLK_PERIOD_AVALON;
  reset_rx <= '0' after CLK_PERIOD_AVALON *8;

  uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine(func);

  clock_gen_avalon : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic
    map (
      GC_CLOCK_PERIOD    => CLK_PERIOD_AVALON,
      GC_CLOCK_HIGH_TIME => CLK_PERIOD_AVALON / 2,
      GC_INSTANCE_IDX    => CLK_AVALON
    )
    port
    map (
      clk => av_clk
    );

  clock_gen_elink : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic
    map (
      GC_CLOCK_PERIOD    => CLK_PERIOD_ELINK,
      GC_CLOCK_HIGH_TIME => CLK_PERIOD_ELINK / 2,
      GC_INSTANCE_IDX    => CLK_ELINK
    )
    port
    map (
      clk => elink_clk
    );

  av_rx.channel <= "0";

  rx_dut : entity colibri.aurora_rx(rtl)
    generic
    map (
      g_N_LANES    => g_NUM_LANES,
      g_LANE_WIDTH => g_LANE_WIDTH,
    g_GBX_BUF_SIZE => 20 * c_AURORA_ENC_WIDTH

    )
    port
    map (
      snk_clk_i                     => elink_clk,
      src_clk_i                     => av_clk,
      src_reset_i                   => reset_rx,
      snk_data_i                    => aurora_data_rx,
      snk_valid_i                   => aurora_valid_rx,
      src_sop_o                     => av_rx.start_of_packet,
      src_eop_o                     => av_rx.end_of_packet,
      src_valid_o                   => av_rx.valid,
      src_error_o                   => av_rx.data_error(0),
      src_data_o                    => av_rx.data,
      std_logic_vector(src_empty_o) => av_rx.empty
    );

  tx_dut : entity colibri.aurora_tx(rtl)
    generic
    map (
      g_N_LANES    => g_NUM_LANES,
      g_LANE_WIDTH => g_LANE_WIDTH,
      g_GBX_BUF_SIZE => 20 * c_AURORA_ENC_WIDTH

    )
    port
    map (
      snk_clk_i   => av_clk,
      src_clk_i   => elink_clk,
      snk_reset_i => reset_tx,
      snk_sop_i   => av_tx.start_of_packet,
      snk_eop_i   => av_tx.end_of_packet,
      snk_valid_i => av_tx.valid,
      snk_ready_o => av_tx.ready,
      snk_data_i  => av_tx.data,
      snk_empty_i => unsigned(av_tx.empty),
      src_data_o  => aurora_data_tx,
      src_valid_o => aurora_valid_tx,
      src_ready_i => (others => '1')
    );

  avalon_tx_src : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic
    map (
      GC_VVC_IS_MASTER => true,
      GC_DATA_WIDTH    => c_AURORA_DATA_WIDTH,
      GC_EMPTY_WIDTH   => log2ceil(c_AURORA_DATA_WIDTH / 8),
      GC_INSTANCE_IDX  => AURORA_TX_IDX
    )
    port
    map (
      clk              => av_clk,
      avalon_st_vvc_if => av_tx
    );

  avalon_rx_snk : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic
    map (
      GC_VVC_IS_MASTER        => false,
      GC_DATA_WIDTH           => c_AURORA_DATA_WIDTH,
      GC_EMPTY_WIDTH          => log2ceil(c_AURORA_DATA_WIDTH / 8),
      GC_INSTANCE_IDX         => AURORA_RX_IDX,
      GC_AVALON_ST_BFM_CONFIG => c_AVST_CONFIG
    )
    port
    map (
      clk              => av_clk,
      avalon_st_vvc_if => av_rx
    );

  gen_delay : if g_DELAY_LANE generate

    type delay_t is array (natural range 9 downto 0) of std_logic_vector(g_LANE_WIDTH - 1 downto 0);

    signal aurora_data_ch0  : delay_t;
    signal aurora_valid_ch0 : std_logic_vector(9 downto 0);
  begin

    process (elink_clk) is
    begin

      if rising_edge(elink_clk) then

        for i in 1 to g_NUM_LANES - 1 loop
          aurora_data_rx(i)  <= aurora_data_tx(i);
          aurora_valid_rx(i) <= aurora_valid_tx(i);
        end loop;

        -- delay channel
        for i in 1 to 9 loop
          aurora_data_ch0(i)  <= aurora_data_ch0(i - 1);
          aurora_valid_ch0(i) <= aurora_valid_ch0(i - 1);

        end loop;

        aurora_data_ch0(0)  <= aurora_data_tx(0);
        aurora_data_rx(0)   <= aurora_data_ch0(9);
        aurora_valid_rx(0)  <= aurora_valid_ch0(9);
        aurora_valid_ch0(0) <= aurora_valid_tx(0);
      end if;

    end process;

  elsif g_ERROR_INJECT generate
    signal error : std_logic;
  begin

    process is
    begin

      error <= '0';
      wait for 100 us;
      error <= '1';
      wait for 200 * CLK_PERIOD_ELINK;

    end process;

    process (all) is
    begin

      for i in 0 to g_NUM_LANES - 1 loop
        aurora_data_rx(i)  <= aurora_data_tx(i);
        aurora_valid_rx(i) <= aurora_valid_tx(i);

        if (error) then
          aurora_data_rx(i) <= (others => '0');
        end if;

      end loop;

    end process;

  else generate

    process (all) is
    begin

      for i in 0 to g_NUM_LANES - 1 loop
        aurora_data_rx(i)  <= aurora_data_tx(i);
        aurora_valid_rx(i) <= aurora_valid_tx(i);
      end loop;

    end process;

  end generate gen_delay;

end architecture sim;
