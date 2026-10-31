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

library bitvis_vip_scoreboard;

----------------------------------------------------------------------------------------------------

entity packet_delay_tb is
  generic (
    RUNNER_CFG    : string;
    --! Symbol width
    g_SYM_WIDTH   : positive := 8;
    --! Data width in terms of symbols
    g_DATA_SYM    : positive := 4;
    --! Number of simoultaneous packets to handle
    g_N_PACKETS   : positive := 8;
    --! Width of the delay configuration port in bits
    g_DELAY_WIDTH : positive := 5
  );
end entity packet_delay_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of packet_delay_tb is

  constant c_CLK_PERIOD : time := 10 ns;

  --! Data/empty bus widths in terms of bits
  constant c_DATA_WIDTH  : positive := g_DATA_SYM * g_SYM_WIDTH;
  constant c_EMPTY_WIDTH : positive := maximum(log2ceil(g_DATA_SYM), 1);

  --! Clock and reset
  signal clk : std_logic;
  signal rst : std_logic := '1';

  --! Configurable packet delay
  signal packet_delay : unsigned(g_DELAY_WIDTH - 1 downto 0) := (others => '0');

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

  --! Induce backpressure at the output
  signal backpressure : std_logic := '0';
  signal src_valid    : std_logic;

  ------------------------------------------------------------------------------
  --! Test data
  ------------------------------------------------------------------------------
  --! Maximum packet length in symbols
  constant c_MAX_SYMBOLS    : positive := g_DATA_SYM * 8;
  --! Number of packets to generate
  constant c_N_TEST_PACKETS : positive := g_N_PACKETS * 128;

  --! Generate random symbols for packet payloads
  impure function generate_test_symbols return t_slv_array is

    variable v_out : t_slv_array(0 to c_MAX_SYMBOLS - 1)(g_SYM_WIDTH - 1 downto 0);

  begin

    for i in v_out'range loop
      v_out(i) := random(g_SYM_WIDTH);
    end loop;

    return v_out;

  end function generate_test_symbols;

  constant c_TEST_SYMBOLS : t_slv_array(0 to c_MAX_SYMBOLS - 1)(g_SYM_WIDTH - 1 downto 0) :=
    generate_test_symbols;

  --! Generate random packet lengths
  impure function generate_packet_lengths return pos_array_t is

    variable v_out : pos_array_t(0 to c_N_TEST_PACKETS - 1);

  begin

    for i in v_out'range loop
      v_out(i) := random(1, c_MAX_SYMBOLS);
    end loop;

    return v_out;

  end function generate_packet_lengths;

  constant c_TEST_LENGTHS : pos_array_t(0 to c_N_TEST_PACKETS - 1) := generate_packet_lengths;

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

  ------------------------------------------------------------------------------
  --! Scoreboard for time delay tracking
  ------------------------------------------------------------------------------
  package time_sb_pkg is new bitvis_vip_scoreboard.generic_sb_pkg
    generic map (
      T_ELEMENT         => time,
      ELEMENT_MATCH     => "=",
      TO_STRING_ELEMENT => to_string
    );

  shared variable v_time_sb : time_sb_pkg.t_generic_sb;

begin ----------------------------------------------------------------------------------------------

  -- Generate clocks
  clock_generator(clk, c_CLK_PERIOD);

  ------------------------------------------------------------------------------
  --! Unit under test
  ------------------------------------------------------------------------------
  u_packet_delay : entity colibri.packet_delay
    generic map (
      g_SYM_WIDTH   => g_SYM_WIDTH,
      g_DATA_SYM    => g_DATA_SYM,
      g_N_PACKETS   => g_N_PACKETS,
      g_NUM_BEATS   => g_N_PACKETS * div_ceil(c_MAX_SYMBOLS, g_DATA_SYM),
      g_DELAY_WIDTH => g_DELAY_WIDTH
    )
    port map (
      clk_i   => clk,
      reset_i => rst,

      delay_i => packet_delay,

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
  begin

    -- Release the reset
    wait_num_rising_edge(clk, 10);
    rst <= '0';

    for i in 0 to c_N_TEST_PACKETS - 1 loop
      v_time_sb.add_expected(now);
      avalon_st_transmit(c_TEST_SYMBOLS(0 to c_TEST_LENGTHS(i) - 1),
                         "Transmit packet no." & to_string(i), avst_snk);
    end loop;

    wait;

  end process proc_input;

  ------------------------------------------------------------------------------
  --! Introduce random backpressure
  ------------------------------------------------------------------------------
  proc_backpressure : process is
  begin

    wait until avst_src.end_of_packet;
    wait until avst_src.start_of_packet;

    while not avst_src.end_of_packet loop
      wait_num_rising_edge(clk, 1);
      backpressure <= random(VOID);
    end loop;

    wait_num_rising_edge(clk, 1);
    backpressure <= '0';

  end process proc_backpressure;

  ------------------------------------------------------------------------------
  --! Verify time delays
  ------------------------------------------------------------------------------
  proc_delay_verification : process is

    variable v_time : time;

  begin

    wait until (not rst);

    for i in 0 to c_N_TEST_PACKETS - 1 loop
      packet_delay <= unsigned(random(g_DELAY_WIDTH));
      wait until avst_src.start_of_packet and avst_src.valid;
      wait for c_CLK_PERIOD / 10;
      v_time       := v_time_sb.fetch_expected(VOID);
      check_value(now - v_time >= to_integer(packet_delay) * c_CLK_PERIOD,
                  "Delay verification no." & to_string(i));
      wait until avst_src.end_of_packet and avst_src.valid;
    end loop;

  end process proc_delay_verification;

  ------------------------------------------------------------------------------
  --! VUnit verification process
  ------------------------------------------------------------------------------
  proc_verify : process is
  begin

    -------------------------- VUNIT SETUP --------------------------
    test_runner_setup(runner, RUNNER_CFG);
    v_time_sb.enable(VOID);

    for i in 0 to c_N_TEST_PACKETS - 1 loop
      avalon_st_expect(c_TEST_SYMBOLS(0 to c_TEST_LENGTHS(i) - 1),
                       "Output verification no." & to_string(i), avst_src);
    end loop;

    ------------------------- VUNIT CLEANUP --------------------------
    test_runner_cleanup(runner);

  end process proc_verify;

  test_runner_watchdog(runner, 10 ms);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
