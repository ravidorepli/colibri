-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  context colibri.common;

library vunit_lib;
  context vunit_lib.vunit_context;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_clock_generator;

library bitvis_vip_avalon_st;
  context bitvis_vip_avalon_st.vvc_context;

----------------------------------------------------------------------------------------------------

entity avst_ram_th is
  generic (
    --! Write clock period
    g_WR_CLK_PERIOD : time;
    --! Read clock period
    g_RD_CLK_PERIOD : time;
    --! Word width in bits
    g_DATA_WIDTH    : positive
  );
  port (
    -- Asynchronous reset
    reset_a_i : in    std_logic;

    rd_addr_i   : in    unsigned;  --! Read start address
    rd_length_i : in    unsigned;  --! Read length in words
    rd_start_i  : in    std_logic; --! Read start signal
    rd_stop_i   : in    std_logic  --! Read stop signal
  );
end entity avst_ram_th;

----------------------------------------------------------------------------------------------------

architecture behavioural of avst_ram_th is

  --! Address width in bits
  constant c_ADDR_WIDTH : positive := rd_addr_i'length;

  -- Read and write domain clocks and sync. resets
  signal wr_clk   : std_logic;
  signal wr_reset : std_logic;
  signal rd_clk   : std_logic;
  signal rd_reset : std_logic;

  -- RAM write interface
  signal wr_en   : std_logic;
  signal wr_addr : rd_addr_i'subtype;
  signal wr_data : std_logic_vector(g_DATA_WIDTH - 1 downto 0);

  -- RAM read interface
  signal rd_en   : std_logic;
  signal rd_addr : rd_addr_i'subtype;
  signal rd_data : std_logic_vector(g_DATA_WIDTH - 1 downto 0);

  constant c_VVC_EMPTY_WIDTH : positive := MAXIMUM(1, LOG2CEIL(g_DATA_WIDTH / 8));

  -- Avalon stream from the master VVC
  signal avst_vvc_master : t_avalon_st_if(channel(c_ADDR_WIDTH - 1 downto 0),
                                           data(g_DATA_WIDTH - 1 downto 0),
                                           data_error(0 downto 0),
                                           empty(c_VVC_EMPTY_WIDTH - 1 downto 0)) :=
         init_avalon_st_if_signals(true, c_ADDR_WIDTH, g_DATA_WIDTH, 1, c_VVC_EMPTY_WIDTH);
  -- Avalon stream to the slave VVC
  signal avst_vvc_slave  : t_avalon_st_if(channel(0 downto 0),
                                           data(g_DATA_WIDTH - 1 downto 0),
                                           data_error(0 downto 0),
                                           empty(c_VVC_EMPTY_WIDTH - 1 downto 0)) :=
         init_avalon_st_if_signals(false, 1, g_DATA_WIDTH, 1, c_VVC_EMPTY_WIDTH);

begin ----------------------------------------------------------------------------------------------

  uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

  ------------------------------------------------------------------------------
  --! Clock generators
  ------------------------------------------------------------------------------
  wr_clock_generator_vvc : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic map (
      GC_INSTANCE_IDX    => 0,
      GC_CLOCK_NAME      => "wr_clk",
      GC_CLOCK_PERIOD    => g_WR_CLK_PERIOD,
      GC_CLOCK_HIGH_TIME => g_WR_CLK_PERIOD / 2
    )
    port map (
      clk => wr_clk
    );

  wr_synchro_reset : entity colibri.synchro_reset
    port map (
      clk_i   => wr_clk,
      reset_i => reset_a_i,
      reset_o => wr_reset
    );

  rd_clock_generator_vvc : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic map (
      GC_INSTANCE_IDX    => 1,
      GC_CLOCK_NAME      => "rd_clk",
      GC_CLOCK_PERIOD    => g_RD_CLK_PERIOD,
      GC_CLOCK_HIGH_TIME => g_RD_CLK_PERIOD / 2
    )
    port map (
      clk => rd_clk
    );

  rd_synchro_reset : entity colibri.synchro_reset
    port map (
      clk_i   => rd_clk,
      reset_i => reset_a_i,
      reset_o => rd_reset
    );

  ------------------------------------------------------------------------------
  --! Avalon-ST VVC master provides the input
  ------------------------------------------------------------------------------
  -- Avalon Stream VVC
  u_avalon_st_vvc_master : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic map (
      GC_VVC_IS_MASTER    => true,
      GC_CHANNEL_WIDTH    => c_ADDR_WIDTH,
      GC_DATA_WIDTH       => g_DATA_WIDTH,
      GC_DATA_ERROR_WIDTH => 1,
      GC_EMPTY_WIDTH      => c_VVC_EMPTY_WIDTH,
      GC_INSTANCE_IDX     => 0
    )
    port map (
      clk              => wr_clk,
      avalon_st_vvc_if => avst_vvc_master
    );

  avst_vvc_master.ready <= '1';

  ------------------------------------------------------------------------------
  --! Unit under test: Write
  ------------------------------------------------------------------------------
  uut_avst_ram_write : entity colibri.avst_ram_write
    generic map (
      g_DATA_WIDTH => g_DATA_WIDTH,
      g_ADDR_WIDTH => c_ADDR_WIDTH
    )
    port map (
      clk_i   => wr_clk,
      reset_i => wr_reset,

      start_addr_i => unsigned(avst_vvc_master.channel),
      snk_sop_i    => avst_vvc_master.start_of_packet,
      snk_eop_i    => avst_vvc_master.end_of_packet,
      snk_data_i   => avst_vvc_master.data,
      snk_valid_i  => avst_vvc_master.valid,

      wr_en_o   => wr_en,
      wr_addr_o => wr_addr,
      wr_data_o => wr_data
    );

  ------------------------------------------------------------------------------
  --! Dual port RAM
  ------------------------------------------------------------------------------
  u_simple_dpram : entity colibri.simple_dpram
    generic map (
      g_DATA_WIDTH => g_DATA_WIDTH,
      g_N_WORDS    => 2 ** c_ADDR_WIDTH
    )
    port map (
      wrclk_i => wr_clk,
      rdclk_i => rd_clk,

      wren_i   => wr_en,
      wraddr_i => wr_addr,
      wrdata_i => wr_data,

      rden_i   => rd_en,
      rdaddr_i => rd_addr,
      rddata_o => rd_data
    );

  ------------------------------------------------------------------------------
  --! Unit under test: Read
  ------------------------------------------------------------------------------
  uut_avst_ram_read : entity colibri.avst_ram_read
    generic map (
      g_BYTE_WIDTH => 8,
      g_WORD_BYTES => g_DATA_WIDTH / 8,
      g_RAM_DEPTH  => 2 ** c_ADDR_WIDTH
    )
    port map (
      clk_i   => rd_clk,
      reset_i => rd_reset,

      src_data_o                    => avst_vvc_slave.data,
      std_logic_vector(src_empty_o) => avst_vvc_slave.empty,
      src_eop_o                     => avst_vvc_slave.end_of_packet,
      src_sop_o                     => avst_vvc_slave.start_of_packet,
      src_valid_o                   => avst_vvc_slave.valid,
      src_ready_i                   => avst_vvc_slave.ready,

      rd_en_o   => rd_en,
      rd_addr_o => rd_addr,
      rd_data_i => rd_data,

      start_addr_i => rd_addr_i,
      length_i     => rd_length_i,
      start_i      => rd_start_i,
      stop_i       => rd_stop_i,
      busy_o       => open
    );

  avst_vvc_slave.channel <= (others => '0');

  ------------------------------------------------------------------------------
  --! Avalon-ST VVC slave receives and checks the output
  ------------------------------------------------------------------------------
  u_avalon_st_vvc_slave : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic map (
      GC_VVC_IS_MASTER    => false,
      GC_CHANNEL_WIDTH    => 1,
      GC_DATA_WIDTH       => g_DATA_WIDTH,
      GC_DATA_ERROR_WIDTH => 1,
      GC_EMPTY_WIDTH      => c_VVC_EMPTY_WIDTH,
      GC_INSTANCE_IDX     => 1
    )
    port map (
      clk              => rd_clk,
      avalon_st_vvc_if => avst_vvc_slave
    );

end architecture behavioural;

----------------------------------------------------------------------------------------------------
