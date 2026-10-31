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

library bitvis_vip_avalon_st;
  use bitvis_vip_avalon_st.avalon_st_bfm_pkg.all;

----------------------------------------------------------------------------------------------------

entity avst_fifo_tb is
  generic (
    RUNNER_CFG     : string;
    --! Seed for random input data generation
    g_SEED         : positive;
    --! Symbol width
    g_SYM_WIDTH    : positive;
    --! Data width in terms of symbols
    g_DATA_SYM     : positive;
    --! Specify whether sink and source clocks are asynchronous
    g_ASYNC_CLOCKS : boolean
  );
end entity avst_fifo_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of avst_fifo_tb is

  constant c_SNK_CLK_PERIOD : time := 10 ns;
  constant c_SRC_CLK_PERIOD : time := 8 ns;

  --! Data/empty bus widths in terms of bits
  constant c_DATA_WIDTH  : positive := g_DATA_SYM * g_SYM_WIDTH;
  constant c_EMPTY_WIDTH : positive := maximum(log2ceil(g_DATA_SYM), 1);

  --! Clocks and reset
  signal snk_clk   : std_logic;
  signal src_clk   : std_logic;
  signal snk_reset : std_logic := '0';

  --! Avalon stream input
  signal avst_snk : t_avalon_st_if
         (
          channel(0 downto 0),
          data(c_DATA_WIDTH - 1 downto 0),
          data_error(0 downto 0),
          empty(c_EMPTY_WIDTH - 1 downto 0)
        ) := init_avalon_st_if_signals(true, 1, c_DATA_WIDTH, 1, c_EMPTY_WIDTH);

  --! Avalon stream output
  signal avst_src : t_avalon_st_if
         (
          channel(0 downto 0),
          data(c_DATA_WIDTH - 1 downto 0),
          data_error(0 downto 0),
          empty(c_EMPTY_WIDTH - 1 downto 0)
        ) := init_avalon_st_if_signals(true, 1, c_DATA_WIDTH, 1, c_EMPTY_WIDTH);

  ------------------------------------------------------------------------------
  --! Test data packets
  ------------------------------------------------------------------------------
  --! Maximum packet length in terms of symbols
  constant c_MAX_PACKET_LEN : positive := 1024;

  type slv_array_2d_t is array (natural range <>) of t_slv_array;

  --! Array of incremental packets; their lengths increase by 1 byte
  signal inc_packets : slv_array_2d_t(0 to g_DATA_SYM)(0 to c_MAX_PACKET_LEN)(g_SYM_WIDTH - 1 downto 0);

  --! Number of random packets to generate
  constant c_NUM_RAND_PACKETS : positive := 10;
  --! Array of random packet lengths in bytes (to be randomply generated)
  signal rand_packet_lens     : pos_array_t(0 to c_NUM_RAND_PACKETS - 1);
  --! Array of random packets; each packet is an array of bytes
  signal rand_packets         : slv_array_2d_t(0 to c_NUM_RAND_PACKETS - 1)
         (0 to c_MAX_PACKET_LEN)(g_SYM_WIDTH - 1 downto 0);

  ------------------------------------------------------------------------------
  --! UVVM Avalon-ST Bus Functional Model (BFM) related
  ------------------------------------------------------------------------------
  --! Avalon BFM configuration (mainly to set the `symbol_width`)
  constant c_AVALON_ST_BFM_CONFIG : t_avalon_st_bfm_config :=
  (
    max_wait_cycles          => 100,
    max_wait_cycles_severity => ERROR,
    clock_period             => c_SNK_CLK_PERIOD,
    clock_period_margin      => 0 ns,
    clock_margin_severity    => TB_ERROR,
    setup_time               => c_SNK_CLK_PERIOD / 4,
    hold_time                => c_SNK_CLK_PERIOD / 4,
    bfm_sync                 => SYNC_ON_CLOCK_ONLY,
    match_strictness         => MATCH_EXACT,
    symbol_width             => g_SYM_WIDTH,
    first_symbol_in_msb      => true,
    max_channel              => 0,
    use_packet_transfer      => true,
    id_for_bfm               => ID_BFM
  );

  --! Transmit method overload (for simplified calls)

  procedure avalon_st_transmit (
    constant data_array   : in t_slv_array;
    constant msg          : in string;
    signal   avalon_st_if : inout t_avalon_st_if
  ) is
  begin

    avalon_st_transmit("0", data_array, msg, snk_clk, avalon_st_if,
                       C_BFM_SCOPE, shared_msg_id_panel, c_AVALON_ST_BFM_CONFIG);

  end procedure avalon_st_transmit;

  --! Transmit method overload (for simplified calls)

  procedure avalon_st_expect (
    constant data_array   : in t_slv_array;
    constant msg          : in string;
    signal   avalon_st_if : inout t_avalon_st_if
  ) is
  begin

    avalon_st_expect("0", data_array, msg, src_clk, avalon_st_if,
                     error, C_BFM_SCOPE, shared_msg_id_panel, c_AVALON_ST_BFM_CONFIG);

  end procedure avalon_st_expect;

begin ----------------------------------------------------------------------------------------------

  -- Set the seed for random generators
  randomize(g_SEED, 42);

  -- Generate clocks
  clock_generator(snk_clk, c_SNK_CLK_PERIOD);

  gen_src_clk : if g_ASYNC_CLOCKS generate
    clock_generator(src_clk, c_SRC_CLK_PERIOD);
  else generate
    src_clk <= snk_clk;
  end generate gen_src_clk;

  ------------------------------------------------------------------------------
  --! Unit under test
  ------------------------------------------------------------------------------
  avst_fifo_inst : entity colibri.avst_fifo
    generic map (
      g_SYM_WIDTH    => g_SYM_WIDTH,
      g_DATA_SYM     => g_DATA_SYM,
      g_ASYNC_CLOCKS => g_ASYNC_CLOCKS
    )
    port map (
      snk_clk_i   => snk_clk,
      snk_reset_i => snk_reset,

      snk_ready_o => avst_snk.ready,
      snk_valid_i => avst_snk.valid,
      snk_sop_i   => avst_snk.start_of_packet,
      snk_eop_i   => avst_snk.end_of_packet,
      snk_empty_i => unsigned(avst_snk.empty),
      snk_data_i  => avst_snk.data,

      src_clk_i                     => src_clk,
      src_ready_i                   => avst_src.ready,
      src_valid_o                   => avst_src.valid,
      src_sop_o                     => avst_src.start_of_packet,
      src_eop_o                     => avst_src.end_of_packet,
      std_logic_vector(src_empty_o) => avst_src.empty,
      src_data_o                    => avst_src.data
    );

  avst_src.channel    <= (others => '0');
  avst_src.data_error <= (others => '0');

  ------------------------------------------------------------------------------
  --! Data input process
  ------------------------------------------------------------------------------
  proc_input : process is

    variable v_packet_len : integer range 1 to c_MAX_PACKET_LEN;

  begin

    -- Generate incremental packets
    for i in inc_packets'range loop

      for j in 0 to i loop
        inc_packets(i)(j) <= std_logic_vector(to_unsigned(j, g_SYM_WIDTH));
      end loop;

    end loop;

    -- Generate random packet lengths and random data bytes
    for i in rand_packet_lens'range loop
      v_packet_len        := random(1, c_MAX_PACKET_LEN);
      rand_packet_lens(i) <= v_packet_len;

      for j in 0 to v_packet_len - 1 loop
        rand_packets(i)(j) <= random(g_SYM_WIDTH);
      end loop;

    end loop;

    -- Generate the initial reset pulse
    gen_pulse(snk_reset, snk_clk, 10, "Initial reset");

    -- Transmit incremental data packets
    for i in inc_packets'range loop
      avalon_st_transmit(inc_packets(i)(0 to i), "Incremental input " & to_string(i), avst_snk);
      wait_num_rising_edge(snk_clk, 10);
    end loop;

    -- Transmit random data packets
    for i in rand_packets'range loop
      avalon_st_transmit(rand_packets(i)(0 to rand_packet_lens(i) - 1), "Random input " & to_string(i), avst_snk);
      wait_num_rising_edge(snk_clk, 10);
    end loop;

    wait;

  end process proc_input;

  ------------------------------------------------------------------------------
  --! VUnit verification process
  ------------------------------------------------------------------------------
  proc_verify : process is
  begin

    -------------------------- VUNIT SETUP --------------------------
    test_runner_setup(runner, RUNNER_CFG);

    -- Verify incremental output data packets
    for i in inc_packets'range loop
      avalon_st_expect(inc_packets(i)(0 to i),
                       "Incremental output verification " & to_string(i), avst_src);
    end loop;

    -- Verify random output data packets
    for i in rand_packets'range loop
      avalon_st_expect(rand_packets(i)(0 to rand_packet_lens(i) - 1),
                       "Random output verification " & to_string(i), avst_src);
    end loop;

    ------------------------- VUNIT CLEANUP --------------------------
    test_runner_cleanup(runner);

  end process proc_verify;

  test_runner_watchdog(runner, 10 ms);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
