-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library vunit_lib;
  context vunit_lib.vunit_context;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_clock_generator;
  context bitvis_vip_clock_generator.vvc_context;

library bitvis_vip_axistream;
  context bitvis_vip_axistream.vvc_context;

library bitvis_vip_spi;
  context bitvis_vip_spi.vvc_context;

library colibri;
  context colibri.common;

use work.tb_pkg.all;

entity spi_master_th is
  generic (
    g_SCK_PHASE    : std_logic;
    g_SCK_POLARITY : std_logic
  );
end entity spi_master_th;

architecture sim of spi_master_th is

  -- Ports
  signal clk   : std_logic := '1';
  signal reset : std_logic := '1';

  signal axis_snk : t_axis_if;
  signal axis_src : t_axis_if;
  signal mspi     : t_spi_if;

  constant c_SPI_FREQ   : natural          := 1_000_000;
  constant c_SPI_PERIOD : time             := 1 sec / c_SPI_FREQ;
  constant c_SPI_CFG    : t_spi_bfm_config :=
  (
    CPOL             => g_SCK_POLARITY,
    CPHA             => g_SCK_PHASE,
    spi_bit_time     => c_SPI_PERIOD, -- Make sure we notice if we forget to set bit time.
    ss_n_to_sclk     => c_SPI_PERIOD / 2,
    sclk_to_ss_n     => c_SPI_PERIOD / 2,
    inter_word_delay => c_SPI_PERIOD / 2,
    match_strictness => MATCH_EXACT,
    id_for_bfm       => ID_BFM,
    id_for_bfm_wait  => ID_BFM_WAIT,
    id_for_bfm_poll  => ID_BFM_POLL
  );

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

  spi_master_inst : entity colibri.spi_master
    generic map (
      g_CLOCK_PERIOD  => c_CLK_PERIOD_40,
      g_SCK_FREQUENCY => c_SPI_FREQ,
      g_WORD_SIZE     => c_DATA_WIDTH,
      g_SCK_POLARITY  => g_SCK_POLARITY,
      g_SCK_PHASE     => g_SCK_PHASE
    )
    port map (
      clk_i => clk,
      -- reset_i     => reset,
      miso_i      => mspi.miso,
      mosi_o      => mspi.mosi,
      cs_n_o      => mspi.ss_n,
      sck_o       => mspi.sclk,
      src_data_o  => axis_snk.tdata,
      src_valid_o => axis_snk.tvalid,
      snk_data_i  => axis_src.tdata,
      snk_valid_i => axis_src.tvalid,
      snk_ready_o => axis_src.tready
    );

  axis_snk.tkeep <= (others => '1');
  axis_snk.tlast <= '1';

  axistream_tx_src : entity bitvis_vip_axistream.axistream_vvc
    generic map (
      -- When true: This VVC is an AXI4 Stream master. Data is output from BFM.
      -- When false: This VVC is an AXI4 Stream slave. Data is input to BFM.
      GC_VVC_IS_MASTER        => true,
      GC_DATA_WIDTH           => c_DATA_WIDTH,
      GC_INSTANCE_IDX         => c_AXIS_SRC_IDX,
      GC_AXISTREAM_BFM_CONFIG => c_AXIS_CONF
    )
    port map (
      clk              => clk,
      axistream_vvc_if => axis_src
    );

  axistream_rx_snk : entity bitvis_vip_axistream.axistream_vvc
    generic map (
      -- When true: This VVC is an AXI4 Stream master. Data is output from BFM.
      -- When false: This VVC is an AXI4 Stream slave. Data is input to BFM.
      GC_VVC_IS_MASTER        => false,
      GC_DATA_WIDTH           => c_DATA_WIDTH,
      GC_INSTANCE_IDX         => c_AXIS_SNK_IDX,
      GC_AXISTREAM_BFM_CONFIG => c_AXIS_CONF

    )
    port map (
      clk              => clk,
      axistream_vvc_if => axis_snk
    );

  spi_vvc_inst : entity bitvis_vip_spi.spi_vvc
    generic map (
      GC_DATA_WIDTH   => c_DATA_WIDTH,
      GC_INSTANCE_IDX => c_SPI_IDX,
      GC_MASTER_MODE  => false,
      GC_SPI_CONFIG   => c_SPI_CFG
    )
    port map (
      spi_vvc_if => mspi
    );

end architecture sim;
