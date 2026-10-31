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

entity avst_ram_read_unaligned_th is
  generic (
    g_CLK_PERIOD : time;
    g_BYTE_WIDTH : positive;
    g_WORD_BYTES : positive;
    g_RAM_DEPTH  : positive
  );
  port (
    --! Clock and reset
    clk_i   : in    std_logic;
    reset_i : in    std_logic;

    --! Induce backpressure between the UUT and the VVC
    back_pressure_i : in    std_logic;

    --! Reader control
    start_addr_i : in    unsigned(log2ceil(g_RAM_DEPTH * g_WORD_BYTES) - 1 downto 0);
    rd_length_i  : in    unsigned(log2ceil(g_RAM_DEPTH * g_WORD_BYTES) downto 0);
    rd_start_i   : in    std_logic;
    rd_busy_o    : out   std_logic;

    --! RAM read interface
    rd_en_o   : out   std_logic;
    rd_addr_o : out   unsigned(log2ceil(g_RAM_DEPTH) - 1 downto 0);
    rd_data_i : in    std_logic_vector
  );
end entity avst_ram_read_unaligned_th;

----------------------------------------------------------------------------------------------------

architecture behavioural of avst_ram_read_unaligned_th is

  --! Word width in bits
  constant c_DATA_WIDTH : positive := g_WORD_BYTES * g_BYTE_WIDTH;

  --! Avalon empty bus width
  constant c_VVC_EMPTY_WIDTH : positive := maximum(1, log2ceil(c_DATA_WIDTH / g_BYTE_WIDTH));

  -- Avalon stream to the slave VVC
  signal avst_vvc_slave : t_avalon_st_if(channel(0 downto 0),
                                          data(c_DATA_WIDTH - 1 downto 0),
                                          data_error(0 downto 0),
                                          empty(c_VVC_EMPTY_WIDTH - 1 downto 0)) :=
         init_avalon_st_if_signals(false, 1, c_DATA_WIDTH, 1, c_VVC_EMPTY_WIDTH);

  --! The Avalon-ST valid and ready signals
  signal avst_ready : std_logic;
  signal avst_valid : std_logic;

begin ----------------------------------------------------------------------------------------------

  uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

  --------------------------------------------------------------------------------------------------
  --! Unit Under Test
  --------------------------------------------------------------------------------------------------
  uut_avst_ram_read_unaligned : entity colibri.avst_ram_read_unaligned
    generic map (
      g_BYTE_WIDTH => g_BYTE_WIDTH,
      g_WORD_BYTES => g_WORD_BYTES,
      g_RAM_DEPTH  => g_RAM_DEPTH
    )
    port map (
      clk_i   => clk_i,
      reset_i => reset_i,

      src_data_o                    => avst_vvc_slave.data,
      std_logic_vector(src_empty_o) => avst_vvc_slave.empty,
      src_sop_o                     => avst_vvc_slave.start_of_packet,
      src_eop_o                     => avst_vvc_slave.end_of_packet,
      src_valid_o                   => avst_valid,
      src_ready_i                   => avst_ready,

      start_addr_i => start_addr_i,
      length_i     => rd_length_i,
      start_i      => rd_start_i,
      busy_o       => rd_busy_o,

      rd_en_o   => rd_en_o,
      rd_addr_o => rd_addr_o,
      rd_data_i => rd_data_i
    );

  -- Mask the valid and ready to create backpressure
  avst_ready             <= avst_vvc_slave.ready and not back_pressure_i;
  avst_vvc_slave.valid   <= avst_valid and not back_pressure_i;
  avst_vvc_slave.channel <= (others => '0');

  ------------------------------------------------------------------------------
  --! Avalon-ST VVC slave receives and checks the output
  ------------------------------------------------------------------------------
  u_avalon_st_vvc_slave : entity bitvis_vip_avalon_st.avalon_st_vvc
    generic map (
      GC_VVC_IS_MASTER    => false,
      GC_CHANNEL_WIDTH    => 1,
      GC_DATA_WIDTH       => c_DATA_WIDTH,
      GC_DATA_ERROR_WIDTH => 1,
      GC_EMPTY_WIDTH      => c_VVC_EMPTY_WIDTH,
      GC_INSTANCE_IDX     => 0
    )
    port map (
      clk              => clk_i,
      avalon_st_vvc_if => avst_vvc_slave
    );

end architecture behavioural;

----------------------------------------------------------------------------------------------------
