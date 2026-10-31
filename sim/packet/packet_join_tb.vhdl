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

entity packet_join_tb is
  generic (
    RUNNER_CFG  : string;
    --! Seed for random input data generation
    g_SEED      : positive := 8;
    --! Symbol width
    g_SYM_WIDTH : positive := 8;
    --! Data width in terms of symbols
    g_DATA_SYM  : positive := 4
  );
end entity packet_join_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of packet_join_tb is

  constant c_CLK_PERIOD : time := 10 ns;

  --! Data/empty bus widths in terms of bits
  constant c_DATA_WIDTH  : positive := g_DATA_SYM * g_SYM_WIDTH;
  constant c_EMPTY_WIDTH : positive := maximum(log2ceil(g_DATA_SYM), 1);

  --! Clock and reset
  signal clk : std_logic;
  signal rst : std_logic := '1';

  signal last_packet : std_logic := '0';

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
  --! Test data symbols
  ------------------------------------------------------------------------------
  --! Number of test symbols
  constant c_NUM_TEST_SYM : positive := 1024;

  impure function generate_test_symbols return t_slv_array is

    variable v_out : t_slv_array(0 to c_NUM_TEST_SYM - 1)(g_SYM_WIDTH - 1 downto 0);

  begin

    for i in v_out'range loop
      v_out(i) := random(g_SYM_WIDTH);
    end loop;

    return v_out;

  end function generate_test_symbols;

  constant c_TEST_SYMBOLS : t_slv_array(0 to c_NUM_TEST_SYM - 1)(g_SYM_WIDTH - 1 downto 0) :=
    generate_test_symbols;

  ------------------------------------------------------------------------------
  --! UVVM Avalon-ST Bus Functional Model (BFM) related
  ------------------------------------------------------------------------------
  --! Avalon BFM configuration (mainly to set the `symbol_width`)
  constant c_AVALON_ST_BFM_CONFIG : t_avalon_st_bfm_config :=
  (
    max_wait_cycles          => 100,
    max_wait_cycles_severity => ERROR,
    clock_period             => c_CLK_PERIOD,
    clock_period_margin      => 0 ns,
    clock_margin_severity    => TB_ERROR,
    setup_time               => c_CLK_PERIOD / 4,
    hold_time                => c_CLK_PERIOD / 4,
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

    avalon_st_transmit("0", data_array, msg, clk, avalon_st_if,
                       C_BFM_SCOPE, shared_msg_id_panel, c_AVALON_ST_BFM_CONFIG);

  end procedure avalon_st_transmit;

  --! Transmit method overload (for simplified calls)

  procedure avalon_st_expect (
    constant data_array   : in t_slv_array;
    constant msg          : in string;
    signal   avalon_st_if : inout t_avalon_st_if
  ) is
  begin

    avalon_st_expect("0", data_array, msg, clk, avalon_st_if,
                     error, C_BFM_SCOPE, shared_msg_id_panel, c_AVALON_ST_BFM_CONFIG);

  end procedure avalon_st_expect;

  signal backpressure : std_logic := '0';
  signal src_valid    : std_logic;

begin ----------------------------------------------------------------------------------------------

  -- Set the seed for random generators
  randomize(g_SEED, 42);

  -- Generate clocks
  clock_generator(clk, c_CLK_PERIOD);

  ------------------------------------------------------------------------------
  --! Unit under test
  ------------------------------------------------------------------------------
  uut_packet_join : entity colibri.packet_join
    generic map (
      g_SYM_WIDTH => g_SYM_WIDTH,
      g_DATA_SYM  => g_DATA_SYM
    )
    port map (
      clk_i   => clk,
      reset_i => rst,

      last_i => last_packet,

      snk_data_i  => avst_snk.data,
      snk_empty_i => unsigned(avst_snk.empty),
      snk_sop_i   => avst_snk.start_of_packet,
      snk_eop_i   => avst_snk.end_of_packet,
      snk_valid_i => avst_snk.valid,
      snk_ready_o => avst_snk.ready,

      src_data_o                    => avst_src.data,
      std_logic_vector(src_empty_o) => avst_src.empty,
      src_sop_o                     => avst_src.start_of_packet,
      src_eop_o                     => avst_src.end_of_packet,
      src_valid_o                   => src_valid,
      src_ready_i                   => avst_src.ready and not backpressure
    );

  avst_src.valid   <= src_valid and not backpressure;
  avst_src.channel <= (others => '0');

  ------------------------------------------------------------------------------
  --! Data input process
  ------------------------------------------------------------------------------
  proc_input : process is

    constant c_MAX_IN_SYM : positive := div_ceil(c_NUM_TEST_SYM, 32);

    variable v_remaining_sim : natural;
    variable v_in_sym        : positive;

  begin

    -- Release the reset
    wait_num_rising_edge(clk, 10);
    rst <= '0';

    for i in 0 to 1 loop
      v_remaining_sim := c_NUM_TEST_SYM;

      while v_remaining_sim > c_MAX_IN_SYM loop
        v_in_sym        := random(1, c_MAX_IN_SYM);
        avalon_st_transmit(c_TEST_SYMBOLS(c_NUM_TEST_SYM - v_remaining_sim to
                           c_NUM_TEST_SYM - v_remaining_sim + v_in_sym - 1),
                           "Input transmit, remaining "
                           & to_string(v_remaining_sim) & "/" & to_string(c_NUM_TEST_SYM), avst_snk);
        v_remaining_sim := v_remaining_sim - v_in_sym;
      end loop;

      last_packet <= '1';
      avalon_st_transmit(c_TEST_SYMBOLS(c_NUM_TEST_SYM - v_remaining_sim to c_TEST_SYMBOLS'right),
                         "Input transmit, last packet", avst_snk);
      last_packet <= '0';

      wait_num_rising_edge(clk, 10);
    end loop;

    wait;

  end process proc_input;

  proc_backpressure : process is
  begin

    wait until avst_src.end_of_packet;   -- Skip a packet
    wait until avst_src.start_of_packet; -- Wait for tne next

    -- Introduce random backpressure
    while not avst_src.end_of_packet loop
      wait_num_rising_edge(clk, 1);
      backpressure <= random(VOID);
    end loop;

    wait_num_rising_edge(clk, 1);
    backpressure <= '0';

  end process proc_backpressure;

  ------------------------------------------------------------------------------
  --! VUnit verification process
  ------------------------------------------------------------------------------
  proc_verify : process is
  begin

    -------------------------- VUNIT SETUP --------------------------
    test_runner_setup(runner, RUNNER_CFG);

    avalon_st_expect(c_TEST_SYMBOLS, "Output verification, seed="
                     & to_string(g_SEED), avst_src);
    avalon_st_expect(c_TEST_SYMBOLS, "Output verification (with backpressure), seed="
                     & to_string(g_SEED), avst_src);

    ------------------------- VUNIT CLEANUP --------------------------
    test_runner_cleanup(runner);

  end process proc_verify;

  test_runner_watchdog(runner, 10 ms);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
