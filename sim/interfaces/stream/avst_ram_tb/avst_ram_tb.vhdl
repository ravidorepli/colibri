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

entity avst_ram_tb is
  generic (
    RUNNER_CFG : string;

    --! Write clock period
    g_WR_CLK_PERIOD : time     := 8 ns;
    --! Read clock period
    g_RD_CLK_PERIOD : time     := 10 ns;
    --! Word width in bits
    g_DATA_WIDTH    : positive := 32;
    --! Address width in bits
    g_ADDR_WIDTH    : positive := 8
  );
end entity avst_ram_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of avst_ram_tb is

  --! Memory size in words
  constant c_MEM_WORDS : positive := 2 ** g_ADDR_WIDTH;
  --! Memory size in bytes
  constant c_MEM_BYTES : positive := c_MEM_WORDS * g_DATA_WIDTH / 8;
  --! Length width in bits - covers full RAM depth in terms of bytes
  constant c_LEN_WIDTH : positive := log2ceil(c_MEM_BYTES + 1);

  -- Test harness signals
  signal reset_a   : std_logic                           := '1';
  signal rd_addr   : unsigned(g_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal rd_length : unsigned(c_LEN_WIDTH - 1 downto 0)  := (others => '0');
  signal rd_start  : std_logic                           := '0';
  signal rd_stop   : std_logic                           := '0';

begin ----------------------------------------------------------------------------------------------

  ------------------------------------------------------------------------------
  --! Test harness: instantiates the UUT and the VVCs
  ------------------------------------------------------------------------------
  u_avst_ram_th : entity work.avst_ram_th
    generic map (
      g_WR_CLK_PERIOD => g_WR_CLK_PERIOD,
      g_RD_CLK_PERIOD => g_RD_CLK_PERIOD,
      g_DATA_WIDTH    => g_DATA_WIDTH
    )
    port map (
      reset_a_i   => reset_a,
      rd_addr_i   => rd_addr,
      rd_length_i => rd_length,
      rd_start_i  => rd_start,
      rd_stop_i   => rd_stop
    );

  ------------------------------------------------------------------------------
  --! VUnit verification process
  ------------------------------------------------------------------------------
  proc_verify : process is

    -- Random data to fill the RAM
    variable v_test_data : t_slv_array(0 to c_MEM_WORDS - 1)(g_DATA_WIDTH - 1 downto 0);
    -- Writing order: Writing is done in 4 parts, in mixed order
    constant c_WRITE_SEQ : int_array_t(0 to 3) := (2, 1, 3, 0);

  begin

    -------------------------- VUNIT AND UVVM SETUP ----------------------------
    test_runner_setup(runner, RUNNER_CFG);
    await_uvvm_initialization(VOID);

    -- Generate random test data
    for i in v_test_data'range loop
      v_test_data(i) := random(g_DATA_WIDTH);
    end loop;

    -- Avalon VVC configurations
    shared_avalon_st_vvc_config(0).bfm_config.clock_period := g_WR_CLK_PERIOD;
    shared_avalon_st_vvc_config(0).bfm_config.max_channel  := c_MEM_WORDS;
    shared_avalon_st_vvc_config(1).bfm_config.clock_period := g_RD_CLK_PERIOD;

    -- Start all clocks
    start_clock(CLOCK_GENERATOR_VVCT, ALL_INSTANCES, "Starting clock generators");
    await_completion(CLOCK_GENERATOR_VVCT, ALL_INSTANCES, 1 ms, "Wait for all clocks to start");
    -- Release the reset
    wait for 1 us;
    reset_a <= '0';
    wait for g_WR_CLK_PERIOD;

    -- Write test data to the RAM in 4 packets, out of order
    for i in c_WRITE_SEQ'range loop
      avalon_st_transmit(AVALON_ST_VVCT, 0,
                         std_logic_vector(to_unsigned(c_WRITE_SEQ(i) * c_MEM_WORDS / 4, g_ADDR_WIDTH)),
                         v_test_data(c_WRITE_SEQ(i) * c_MEM_WORDS / 4 to (c_WRITE_SEQ(i) + 1) * c_MEM_WORDS / 4 - 1),
                         "Writing test data to RAM, chunk no." & to_string(i));
      await_completion(AVALON_ST_VVCT, 0, 1 ms, "Wait for data writing to finish");

      if (i = 0) then -- Insert some dead time between 1st two packets
        insert_delay(AVALON_ST_VVCT, 0, 10 * g_WR_CLK_PERIOD);
      end if;

    end loop;

    -- Read test data from the RAM (3 times over)
    rd_addr   <= (others => '0');
    rd_length <= to_unsigned(c_MEM_BYTES, c_LEN_WIDTH);

    for i in 1 to 3 loop
      rd_start <= bool_to_sl(i < 3);
      avalon_st_expect(AVALON_ST_VVCT, 1, v_test_data,
                       "Reading test data from RAM: Iteration no." & to_string(i));
      await_completion(AVALON_ST_VVCT, 1, 1 ms,
                       "Wait for data reading to finish: Iteration no." & to_string(i));
    end loop;

    ------------------------------ VUNIT CLEANUP -------------------------------
    test_runner_cleanup(runner);

  end process proc_verify; -----------------------------------------------------

  test_runner_watchdog(runner, 10 ms);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
