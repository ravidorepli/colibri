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
  context bitvis_vip_clock_generator.vvc_context;

library bitvis_vip_avalon_st;
  context bitvis_vip_avalon_st.vvc_context;

----------------------------------------------------------------------------------------------------

entity avst_ram_be_tb is
  generic (
    RUNNER_CFG : string;

    --! Write clock period
    g_WR_CLK_PERIOD : time := 8 ns;
    --! Read clock period
    g_RD_CLK_PERIOD : time := 10 ns;
    --! Byte width in bits
    g_BYTE_WIDTH    : positive;
    --! Bytes per data word
    g_WORD_BYTES    : positive
  );
end entity avst_ram_be_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of avst_ram_be_tb is

  --! RAM depth in words and bytes (max. allowed by UVVM VVC framework)
  constant c_N_BYTES : positive := 256 - 256 mod g_WORD_BYTES;
  constant c_N_WORDS : positive := c_N_BYTES / g_WORD_BYTES;

  --! Byte address width
  constant c_BYTE_ADDR_WIDTH : positive := log2ceil(c_N_BYTES);

  --! Length width in bits - covers the whole RAM
  constant c_LEN_WIDTH : positive := log2ceil(c_N_BYTES) + 1;

  -- Test harness signals
  signal reset_a       : std_logic                                := '1';
  signal rd_start_addr : unsigned(c_BYTE_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal rd_length     : unsigned(c_LEN_WIDTH - 1 downto 0)       := (others => '0');
  signal rd_start      : std_logic                                := '0';
  signal rd_busy       : std_logic;

  ------------------------------------------------------------------------------
  -- Generate random sequences to fill the RAM and read it
  ------------------------------------------------------------------------------
  --! Addressable packet paramters
  type param_t is record
    addr : integer range 0 to c_N_BYTES - 1; --! Start byte address
    size : positive;                         --! Size in bytes
  end record param_t;

  --! Array of packet  parameters (input sequence)
  type param_array_t is array (natural range <>) of param_t;

  --! Addressable packet sequence generator
  impure function make_random_seq (n_packets : positive) return param_array_t is

    variable v_out      : param_array_t(0 to n_packets - 1);
    constant c_AVG_SIZE : positive := c_N_BYTES / n_packets;

  begin

    v_out(0).addr := 0;

    for i in v_out'left to v_out'right - 1 loop
      v_out(i).size     := c_AVG_SIZE + random(1 - c_AVG_SIZE, 1);
      v_out(i + 1).addr := v_out(i).addr + v_out(i).size;
    end loop;

    v_out(v_out'right).size := c_N_BYTES - v_out(v_out'right).addr;

    return v_out;

  end function make_random_seq;

  --! Write sequence packets
  constant c_N_WR_PACKETS : positive                               := 8;
  constant c_WR_SEQ       : param_array_t(0 to c_N_WR_PACKETS - 1) :=
    make_random_seq(c_N_WR_PACKETS);

  --! Read sequence packets
  constant c_N_RD_PACKETS : positive                               := 7;
  constant c_RD_SEQ       : param_array_t(0 to c_N_RD_PACKETS - 1) :=
    make_random_seq(c_N_RD_PACKETS);

  ------------------------------------------------------------------------------
  -- Generate random test data
  ------------------------------------------------------------------------------

  --! Data generator
  impure function make_random_data return t_slv_array is

    variable v_out : t_slv_array(0 to c_N_BYTES - 1)(g_BYTE_WIDTH - 1 downto 0);

  begin

    for i in v_out'range loop
      v_out(i) := random(g_BYTE_WIDTH);
    end loop;

    return v_out;

  end function make_random_data;

  --! Random data to fill the RAM
  constant c_TEST_DATA : t_slv_array(0 to c_N_BYTES - 1)(g_BYTE_WIDTH - 1 downto 0) :=
    make_random_data;

begin ----------------------------------------------------------------------------------------------

  ------------------------------------------------------------------------------
  --! Test harness: instantiates the UUT and the VVCs
  ------------------------------------------------------------------------------
  u_avst_ram_be_th : entity work.avst_ram_be_th
    generic map (
      g_WR_CLK_PERIOD => g_WR_CLK_PERIOD,
      g_RD_CLK_PERIOD => g_RD_CLK_PERIOD,
      g_BYTE_WIDTH    => g_BYTE_WIDTH,
      g_WORD_BYTES    => g_WORD_BYTES,
      g_N_BYTES       => c_N_BYTES
    )
    port map (
      reset_a_i       => reset_a,
      rd_start_addr_i => rd_start_addr,
      rd_length_i     => rd_length,
      rd_start_i      => rd_start,
      rd_busy_o       => rd_busy
    );

  ------------------------------------------------------------------------------
  --! VUnit verification process
  ------------------------------------------------------------------------------
  proc_verify : process is
  begin

    -------------------------- VUNIT AND UVVM SETUP ----------------------------
    test_runner_setup(runner, RUNNER_CFG);
    await_uvvm_initialization(VOID);

    -- Avalon VVC configurations
    shared_avalon_st_vvc_config(0).bfm_config.symbol_width := g_BYTE_WIDTH;
    shared_avalon_st_vvc_config(1).bfm_config.symbol_width := g_BYTE_WIDTH;
    shared_avalon_st_vvc_config(0).bfm_config.clock_period := g_WR_CLK_PERIOD;
    shared_avalon_st_vvc_config(0).bfm_config.max_channel  := c_N_BYTES;
    shared_avalon_st_vvc_config(1).bfm_config.clock_period := g_RD_CLK_PERIOD;

    -- Start all clocks
    start_clock(CLOCK_GENERATOR_VVCT, ALL_INSTANCES, "Starting clock generators");
    await_completion(CLOCK_GENERATOR_VVCT, ALL_INSTANCES, 1 ms, "Wait for all clocks to start");
    -- Release the reset
    wait for 5 * g_WR_CLK_PERIOD;
    reset_a <= '0';

    -- Write test data to the RAM in multiple packets,
    for i in c_WR_SEQ'right downto c_WR_SEQ'left loop
      avalon_st_transmit(AVALON_ST_VVCT, 0,
                         std_logic_vector(to_unsigned(c_WR_SEQ(i).addr, c_BYTE_ADDR_WIDTH)),
                         c_TEST_DATA(c_WR_SEQ(i).addr to c_WR_SEQ(i).addr + c_WR_SEQ(i).size - 1),
                         "Writing test data to RAM, chunk no." & to_string(i));
      await_completion(AVALON_ST_VVCT, 0, 1 ms, "Wait for data writing to finish");

      if (i = 0) then -- Insert some dead time between 1st two packets
        insert_delay(AVALON_ST_VVCT, 0, 10 * g_WR_CLK_PERIOD);
      end if;

    end loop;

    -- Read test data from the RAM
    for i in c_RD_SEQ'range loop
      await_value(rd_busy, '0', 0 ns, c_N_WORDS * g_RD_CLK_PERIOD,
                  "Read it." & to_string(i) & ": Waiting for busy to fall");
      rd_start_addr <= to_unsigned(c_RD_SEQ(i).addr, rd_start_addr'length);
      rd_length     <= to_unsigned(c_RD_SEQ(i).size, rd_length'length);
      gen_pulse(rd_start, g_RD_CLK_PERIOD, "Read it." & to_string(i) & ": start signal");

      avalon_st_expect(AVALON_ST_VVCT, 1, c_TEST_DATA(c_RD_SEQ(i).addr to
                       c_RD_SEQ(i).addr + c_RD_SEQ(i).size - 1),
                       "Read it." & to_string(i) & ": Reading test data from RAM");
    end loop;

    await_completion(AVALON_ST_VVCT, 1, 1 ms, "Wait for data reading to finish");

    ------------------------------ VUNIT CLEANUP -------------------------------
    test_runner_cleanup(runner);

  end process proc_verify; -----------------------------------------------------

  test_runner_watchdog(runner, 10 ms);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
