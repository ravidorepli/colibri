-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  context colibri.common;
  use colibri.aurora_const.all;

library vunit_lib;
  context vunit_lib.vunit_context;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library bitvis_vip_avalon_st;
  use bitvis_vip_avalon_st.avalon_st_bfm_pkg.all;

----------------------------------------------------------------------------------------------------

entity aurora_throughput_tb is
  generic (
    RUNNER_CFG           : string;
    --! Seed for data packet randomization
    g_SEED               : natural  := 42;
    --! Number of Aurora lanes
    g_N_LANES            : positive := 4;
    --! Aurora lane width
    g_LANE_WIDTH         : positive := 32;
    --! use resource optimized gearbox in the decoder
    g_USE_OPTIMIZED_GBX  : boolean  := true;
    --! Factor, by which the decoder output clock is faster that the lane clock
    g_DEC_CLK_MULTIPLIER : positive := g_N_LANES
  );
end entity aurora_throughput_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of aurora_throughput_tb is

  --! Bit width of the Avalon-ST empty bus
  constant c_EMPTY_WIDTH : positive := maximum(log2ceil(c_AURORA_DATA_WIDTH / 8), 1);

  --! Avalon stream input to encoder
  constant c_ENC_CLK_PERIOD : time      := 10 ns;
  signal   enc_clk          : std_logic := '1';
  signal   enc_reset        : std_logic := '1';

  signal avst_enc : t_avalon_st_if
         (
          channel(0 downto 0),
          data(c_AURORA_DATA_WIDTH - 1 downto 0),
          data_error(0 downto 0),
          empty(c_EMPTY_WIDTH - 1 downto 0)
        ) := init_avalon_st_if_signals(true, 1, c_AURORA_DATA_WIDTH, 1, c_EMPTY_WIDTH);

  --! Transmitted data (between enc and dec)
  constant c_TX_CLK_PERIOD : time      := 25 ns;
  signal   tx_clk          : std_logic := '1';
  signal   tx_reset        : std_logic := '1';
  signal   tx_data         : slv_array_t(0 to g_N_LANES - 1)(g_LANE_WIDTH - 1 downto 0);
  signal   shift_data      : slv_array_t(0 to g_N_LANES - 1)(g_LANE_WIDTH - 1 downto 0);

  --! Avalon stream output from decoder
  constant c_DEC_CLK_PERIOD : time      := c_TX_CLK_PERIOD / g_DEC_CLK_MULTIPLIER;
  signal   dec_clk          : std_logic := '1';
  signal   dec_reset        : std_logic := '1';
  signal   dec_link_up      : std_logic;

  signal avst_dec : t_avalon_st_if
         (
          channel(0 downto 0),
          data(c_AURORA_DATA_WIDTH - 1 downto 0),
          data_error(0 downto 0),
          empty(c_EMPTY_WIDTH - 1 downto 0)
        ) := init_avalon_st_if_signals(false, 1, c_AURORA_DATA_WIDTH, 1, c_EMPTY_WIDTH);

  ------------------------------------------------------------------------------
  --! Test data packets
  ------------------------------------------------------------------------------
  --! Maximum and minimum packet length in terms of bytes
  constant c_MIN_PACKET_LEN : positive := 1024;
  constant c_MAX_PACKET_LEN : positive := 8192;

  type slv_array_2d_t is array (natural range <>) of t_slv_array;

  --! Number of random packets to generate
  constant c_NUM_PACKETS  : positive := 10;
  --! Array of random packet lengths in bytes (to be randomly generated)
  signal rand_packet_lens : pos_array_t(0 to c_NUM_PACKETS - 1);
  --! Array of random packets; each packet is an array of bytes
  signal rand_packets     : slv_array_2d_t(0 to c_NUM_PACKETS - 1)
         (0 to c_MAX_PACKET_LEN)(7 downto 0);

  ------------------------------------------------------------------------------
  --! UVVM Avalon-ST Bus Functional Model (BFM) related
  ------------------------------------------------------------------------------
  --! Avalon BFM configuration
  constant c_AVALON_ST_BFM_CONFIG_ENC : t_avalon_st_bfm_config :=
  (
    max_wait_cycles          => 1000,
    max_wait_cycles_severity => ERROR,
    clock_period             => c_ENC_CLK_PERIOD,
    clock_period_margin      => 0 ns,
    clock_margin_severity    => TB_ERROR,
    setup_time               => c_ENC_CLK_PERIOD / 4,
    hold_time                => c_ENC_CLK_PERIOD / 4,
    bfm_sync                 => SYNC_ON_CLOCK_ONLY,
    match_strictness         => MATCH_EXACT,
    symbol_width             => 8,
    first_symbol_in_msb      => true,
    max_channel              => 0,
    use_packet_transfer      => true,
    id_for_bfm               => ID_BFM
  );
  constant c_AVALON_ST_BFM_CONFIG_DEC : t_avalon_st_bfm_config :=
  (
    max_wait_cycles          => 10000,
    max_wait_cycles_severity => ERROR,
    clock_period             => c_DEC_CLK_PERIOD,
    clock_period_margin      => 0 ns,
    clock_margin_severity    => TB_ERROR,
    setup_time               => c_DEC_CLK_PERIOD / 4,
    hold_time                => c_DEC_CLK_PERIOD / 4,
    bfm_sync                 => SYNC_ON_CLOCK_ONLY,
    match_strictness         => MATCH_EXACT,
    symbol_width             => 8,
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

    avalon_st_transmit("0", data_array, msg, enc_clk, avalon_st_if,
                       C_BFM_SCOPE, shared_msg_id_panel, c_AVALON_ST_BFM_CONFIG_ENC);

  end procedure avalon_st_transmit;

  --! Transmit method overload (for simplified calls)

  procedure avalon_st_expect (
    constant data_array   : in t_slv_array;
    constant msg          : in string;
    signal   avalon_st_if : inout t_avalon_st_if
  ) is
  begin

    avalon_st_expect("0", data_array, msg, dec_clk, avalon_st_if,
                     error, C_BFM_SCOPE, shared_msg_id_panel, c_AVALON_ST_BFM_CONFIG_DEC);

  end procedure avalon_st_expect;

begin

  -- Set the seed for random generators
  randomize(g_SEED, 42);

  -- Generate clock and reset
  clock_generator(enc_clk, c_ENC_CLK_PERIOD);
  clock_generator(tx_clk, c_TX_CLK_PERIOD);
  clock_generator(dec_clk, c_DEC_CLK_PERIOD);

  enc_reset <= '0' after 1 us;
  tx_reset  <= '0' after 1.1 us;
  dec_reset <= '0' after 1.2 us;

  ------------------------------------------------------------------------------
  --! Aurora encoder
  ------------------------------------------------------------------------------
  aurora_tx_inst : entity colibri.aurora_tx
    generic map (
      g_N_LANES    => g_N_LANES,
      g_LANE_WIDTH => g_LANE_WIDTH
    )
    port map (
      snk_clk_i   => enc_clk,
      snk_reset_i => enc_reset,
      src_clk_i   => tx_clk,

      snk_sop_i   => avst_enc.start_of_packet,
      snk_eop_i   => avst_enc.end_of_packet,
      snk_valid_i => avst_enc.valid,
      snk_ready_o => avst_enc.ready,
      snk_data_i  => avst_enc.data,
      snk_empty_i => unsigned(avst_enc.empty),

      src_data_o  => tx_data,
      src_valid_o => open,
      src_ready_i => (others => '1')
    );

  ------------------------------------------------------------------------------
  --! Simulate bit delays on the serial lines
  ------------------------------------------------------------------------------
  gen_lane_shifts : for i in 0 to g_N_LANES - 1 generate
    constant c_BIT_SHIFT : natural := 31 * (i + 1) mod g_LANE_WIDTH;
  begin

    bit_shifter_inst : entity colibri.bit_shifter
      generic map (
        g_DATA_WIDTH => g_LANE_WIDTH,
        g_MSB_RIGHT  => false
      )
      port map (
        clk_i    => tx_clk,
        reset_i  => tx_reset,
        offset_i => to_unsigned(c_BIT_SHIFT, log2ceil(g_LANE_WIDTH)),
        data_i   => tx_data(i),
        data_o   => shift_data(i)
      );

  end generate gen_lane_shifts;

  ------------------------------------------------------------------------------
  --! Aurora decoder
  ------------------------------------------------------------------------------
  aurora_rx_inst : entity colibri.aurora_rx
    generic map (
      g_N_LANES           => g_N_LANES,
      g_LANE_WIDTH        => g_LANE_WIDTH,
      g_USE_OPTIMIZED_GBX => g_USE_OPTIMIZED_GBX
    )
    port map (
      snk_clk_i   => tx_clk,
      src_clk_i   => dec_clk,
      src_reset_i => dec_reset,

      snk_valid_i => (others => '1'),
      snk_data_i  => shift_data,

      src_sop_o                     => avst_dec.start_of_packet,
      src_eop_o                     => avst_dec.end_of_packet,
      src_valid_o                   => avst_dec.valid,
      src_error_o                   => avst_dec.data_error(0),
      src_data_o                    => avst_dec.data,
      std_logic_vector(src_empty_o) => avst_dec.empty,
      src_link_up_o                 => dec_link_up
    );

  avst_dec.channel <= (others => '0');

  ------------------------------------------------------------------------------
  --! Data input process
  ------------------------------------------------------------------------------
  proc_input : process is

    variable v_packet_len  : integer range 1 to c_MAX_PACKET_LEN;
    constant c_INIT_PACKET : t_slv_array(0 to 0)(c_AURORA_DATA_WIDTH - 1 downto 0) :=
    (
      0 => (others => '0')
    );

  begin

    -- Generate random packet lengths and random data bytes
    for i in rand_packet_lens'range loop
      v_packet_len        := random(c_MIN_PACKET_LEN, c_MAX_PACKET_LEN);
      rand_packet_lens(i) <= v_packet_len;

      for j in 0 to v_packet_len - 1 loop
        rand_packets(i)(j) <= random(8);
      end loop;

    end loop;

    -- Wait for Aurora link to be established
    wait until dec_link_up;

    -- Transmit one empty word to initialize the decoder
    avalon_st_transmit(c_INIT_PACKET, "Initial packet", avst_enc);

    -- Transmit random data packets through the encoder
    for i in rand_packets'range loop
      avalon_st_transmit(rand_packets(i)(0 to rand_packet_lens(i) - 1), "Input packet no." & to_string(i), avst_enc);
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

    -- Verify output data packets from the decoder
    for i in rand_packets'range loop
      avalon_st_expect(rand_packets(i)(0 to rand_packet_lens(i) - 1),
                       "Output packet verification no." & to_string(i), avst_dec);
    end loop;

    ------------------------- VUNIT CLEANUP --------------------------
    test_runner_cleanup(runner);

  end process proc_verify;

end architecture behavioural;

----------------------------------------------------------------------------------------------------
