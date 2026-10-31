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

library bitvis_vip_avalon_st;
  context bitvis_vip_avalon_st.vvc_context;

----------------------------------------------------------------------------------------------------

entity avst_ram_read_unaligned_tb is
  generic (
    RUNNER_CFG   : string;
    g_BYTE_WIDTH : positive := 8;
    g_WORD_BYTES : positive := 8;
    g_RAM_DEPTH  : positive := 128 --! RAM depth in terms of words
  );
end entity avst_ram_read_unaligned_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of avst_ram_read_unaligned_tb is

  -- Clock period
  constant c_CLK_PERIOD : time := 10 ns;
  --! Word width in bits
  constant c_DATA_WIDTH : positive := g_WORD_BYTES * g_BYTE_WIDTH;
  --! RAM depth in bytes
  constant c_RAM_BYTES  : positive := g_WORD_BYTES * g_RAM_DEPTH;

  --! Test harness interface signals
  signal clk   : std_logic;
  signal reset : std_logic := '1';

  signal back_pressure : std_logic := '0';

  signal start_addr : unsigned(log2ceil(c_RAM_BYTES) - 1 downto 0) := (others => '0');
  signal rd_length  : unsigned(log2ceil(c_RAM_BYTES) downto 0)     := (others => '0');
  signal rd_start   : std_logic                                    := '0';
  signal rd_busy    : std_logic;

  signal rd_en   : std_logic;
  signal rd_addr : unsigned(log2ceil(g_RAM_DEPTH) - 1 downto 0);
  signal rd_data : std_logic_vector(c_DATA_WIDTH - 1 downto 0) := (others => '0');

begin ----------------------------------------------------------------------------------------------

  randomize(1, 2);

  clock_generator(clk, c_CLK_PERIOD);

  --------------------------------------------------------------------------------------------------
  --! Test harness, containing the UUT and the output Avalon VVC
  --------------------------------------------------------------------------------------------------
  avst_ram_read_unaligned_th_inst : entity work.avst_ram_read_unaligned_th
    generic map (
      g_CLK_PERIOD => c_CLK_PERIOD,
      g_BYTE_WIDTH => g_BYTE_WIDTH,
      g_WORD_BYTES => g_WORD_BYTES,
      g_RAM_DEPTH  => g_RAM_DEPTH
    )
    port map (
      clk_i   => clk,
      reset_i => reset,

      back_pressure_i => back_pressure,

      start_addr_i => start_addr,
      rd_length_i  => rd_length,
      rd_start_i   => rd_start,
      rd_busy_o    => rd_busy,

      rd_en_o   => rd_en,
      rd_addr_o => rd_addr,
      rd_data_i => rd_data
    );

  --------------------------------------------------------------------------------------------------
  --! VUnit verification process (implements VVC sequencer)
  --------------------------------------------------------------------------------------------------
  proc_verify : process is

    --! Simulated RAM contents
    variable v_ram_bytes : t_slv_array(0 to c_RAM_BYTES - 1)(g_BYTE_WIDTH - 1 downto 0);

    --! Read one word the simulated RAM
    procedure read_ram (
      addr : in rd_addr'subtype
    ) is

      constant c_BYTE_ADDR : natural := to_integer(addr) * g_WORD_BYTES;

    begin

      for i in 0 to g_WORD_BYTES - 1 loop
        rd_data(rd_data'left - i * g_BYTE_WIDTH downto rd_data'length - (i + 1) * g_BYTE_WIDTH) <=
          v_ram_bytes(c_BYTE_ADDR + i);
      end loop;

    end procedure read_ram; ------------------------------------------------------------------------

    --! Verify RAM interface, simulate RAM output, verify Avalon output
    procedure simulate_and_verify (
      test_id          : in string;
      add_backpressure : in boolean := false --! Adds random back-pressure
    ) is

      --! RAM word address (for verification)
      variable v_addr : rd_addr'subtype;
      --! Byte-address skew relative to word address
      variable v_skew : natural;
      --! Total number of words to read
      variable v_n_words : positive;
      --! Counts words read from RAM (in the while loop)
      variable v_cnt : natural := 0;
      --! Signal when to read a word from RAM (there might be idle cycled due to back-pressure)
      variable v_read_ram : std_logic;

    begin

      -- Send a start pulse to the component
      gen_pulse(rd_start, clk, 1, test_id & ": Start reading");

      -- Initiate the VVC for reception
      avalon_st_expect(AVALON_ST_VVCT, 0,
                       v_ram_bytes(to_integer(start_addr) to
                       to_integer(start_addr) + to_integer(rd_length) - 1),
                       test_id & ": Check output Avalon Stream");

      -- Calculate word address, byte skew and num. of words to read
      v_addr    := to_unsigned(to_integer(start_addr) / g_WORD_BYTES, v_addr'length);
      v_skew    := to_integer(start_addr) mod g_WORD_BYTES;
      v_n_words := div_ceil(to_integer(rd_length) + v_skew, g_WORD_BYTES);

      -- Main loop: read all the words -----------------------------------------
      while v_cnt < v_n_words loop
        wait for c_CLK_PERIOD / 10;

        if (not back_pressure) then
          check_value(rd_busy, '1', test_id & ", it. " & to_string(v_cnt)& ": Component should be busy");
          check_value(rd_en, '1', test_id & ", it. " & to_string(v_cnt)& ": Reading should be active");
          check_value(rd_addr, v_addr, test_id & ", it. " & to_string(v_cnt)& ": Verify read address");
        else
          check_value(rd_busy, '1', test_id & ", it. " & to_string(v_cnt)& ": Component should be busy");
          check_value(rd_en, '0', test_id & ", it. " & to_string(v_cnt)& ": Reading should pause");
        end if;

        -- Simulate backpressure (not in the first 3CC, before the Avalon output starts)
        if (add_backpressure and v_cnt > 3 and v_cnt < v_n_words - 1) then
          back_pressure <= random(VOID);
        else
          back_pressure <= '0';
        end if;

        v_read_ram := rd_en;
        wait_num_rising_edge(clk, 1);
        -- Simulate RAM output with 1CC delay
        if (v_read_ram) then
          read_ram(v_addr);
          v_addr := v_addr + 1;
          v_cnt  := v_cnt + 1;
        end if;

      end loop; -- Main loop ---------------------------------------------------

      wait for c_CLK_PERIOD / 10;
      check_value(rd_en, '0', test_id & ": Reading should stop");
      wait_num_rising_edge_plus_margin(clk, 3, c_CLK_PERIOD / 10);
      check_value(rd_busy, '0', test_id & ": Component should cease to be busy");

    end procedure simulate_and_verify; -------------------------------------------------------------

  begin

    -------------------------- VUNIT SETUP --------------------------
    test_runner_setup(runner, RUNNER_CFG);
    await_uvvm_initialization(VOID);

    -- Avalon VVC configurations
    shared_avalon_st_vvc_config(0).bfm_config.symbol_width := g_BYTE_WIDTH;
    shared_avalon_st_vvc_config(0).bfm_config.clock_period := c_CLK_PERIOD;

    -- Generate the RAM contents
    for i in v_ram_bytes'range loop
      v_ram_bytes(i) := random(g_BYTE_WIDTH);
    end loop;

    -- Initial reset
    wait_num_rising_edge(clk, 3);
    reset <= '0';

    ------------------------------------------------------------------
    -- TEST 0: Initial state
    ------------------------------------------------------------------
    wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
    check_value(rd_en, '0', "TEST 0: Reading should not be active after the reset");
    check_stable(rd_en, 4 * c_CLK_PERIOD, "TEST 0: Reading should not be active during the reset");
    check_value(rd_busy, '0', "TEST 0: Component should not be busy after the reset");
    check_stable(rd_busy, 4 * c_CLK_PERIOD, "TEST 0: Component should not be busy during the reset");

    ------------------------------------------------------------------
    -- TEST 1: Multi-beat packets
    ------------------------------------------------------------------
    if run("multi_beat") then

      for i in 0 to g_WORD_BYTES - 1 loop

        start_addr <= to_unsigned(random(0, g_RAM_DEPTH / 2) * g_WORD_BYTES + i, start_addr'length);
        rd_length  <= to_unsigned(g_RAM_DEPTH / 2 * g_WORD_BYTES - i, rd_length'length);

        simulate_and_verify("TEST 1, packet " & to_string(i));

      end loop;

      await_completion(AVALON_ST_VVCT, 0, 1 ms, "Waiting for Avalon output to finish");
    end if;

    ------------------------------------------------------------------
    -- TEST 2: Short packets (aligned)
    ------------------------------------------------------------------
    if run("short_aligned") then

      for i in 5 downto 1 loop

        start_addr <= to_unsigned(random(0, g_RAM_DEPTH / 2) * g_WORD_BYTES, start_addr'length);
        rd_length  <= to_unsigned(i * g_WORD_BYTES, rd_length'length);

        simulate_and_verify("TEST 2, size " & to_string(i));

      end loop;

      await_completion(AVALON_ST_VVCT, 0, 1 ms, "Waiting for Avalon output to finish");
    end if;

    ------------------------------------------------------------------
    -- TEST 3: Single-beat packet scenarios (unaligned)
    ------------------------------------------------------------------
    if run("single_beat") then
      -- Single read, unaligned
      start_addr <= to_unsigned(random(0, g_RAM_DEPTH / 2) * g_WORD_BYTES + 1, start_addr'length);
      rd_length  <= to_unsigned(g_WORD_BYTES - 1, rd_length'length);

      simulate_and_verify("TEST 3, 1-read");

      -- Double read
      start_addr <= to_unsigned(random(1, g_RAM_DEPTH / 2) * g_WORD_BYTES - 1, start_addr'length);
      rd_length  <= to_unsigned(2, rd_length'length);

      simulate_and_verify("TEST 3, 2-read");

      await_completion(AVALON_ST_VVCT, 0, 1 ms, "Waiting for Avalon output to finish");
    end if;

    ------------------------------------------------------------------
    -- TEST 4: Short packets (unaligned)
    ------------------------------------------------------------------
    if run("short_unaligned") then

      for i in 2 to 5 loop

        -- Requires one additional read (due to address skew)
        start_addr <= to_unsigned(random(1, g_RAM_DEPTH / 2) * g_WORD_BYTES - 1, start_addr'length);
        rd_length  <= to_unsigned((i - 1) * g_WORD_BYTES + 1, rd_length'length);

        simulate_and_verify("TEST 4, ADD, size " & to_string(i));

        -- No additional read required
        start_addr <= to_unsigned(random(0, g_RAM_DEPTH / 2) * g_WORD_BYTES + 1, start_addr'length);
        rd_length  <= to_unsigned(i * g_WORD_BYTES - 1, rd_length'length);

        simulate_and_verify("TEST 4, NO_ADD, size " & to_string(i));

      end loop;

      await_completion(AVALON_ST_VVCT, 0, 1 ms, "Waiting for Avalon output to finish");
    end if;

    ------------------------------------------------------------------
    -- TEST 5: Max. length packet
    ------------------------------------------------------------------
    if run("max_len") then
      start_addr <= (others => '0');
      rd_length  <= to_unsigned(c_RAM_BYTES, rd_length'length);

      simulate_and_verify("TEST 5");

      await_completion(AVALON_ST_VVCT, 0, 1 ms, "Waiting for Avalon output to finish");
    end if;

    ------------------------------------------------------------------
    -- TEST 6: Back-pressure response
    ------------------------------------------------------------------
    if run("back_pressure") then
      start_addr <= (others => '0');
      rd_length  <= to_unsigned(c_RAM_BYTES, rd_length'length);

      simulate_and_verify("TEST 6", true);

      await_completion(AVALON_ST_VVCT, 0, 1 ms, "Waiting for Avalon output to finish");
    end if;

    ------------------------------------------------------------------
    -- TEST 7: Back-pressure response (edge cases)
    ------------------------------------------------------------------
    if run("back_pressure_edge_cases") then
      -- Single read
      start_addr <= to_unsigned(1, start_addr'length);
      rd_length  <= to_unsigned(1, rd_length'length);
      gen_pulse(rd_start, clk, 1, "TEST 7a: Start reading");

      avalon_st_expect(AVALON_ST_VVCT, 0, v_ram_bytes(1 to 1), "TEST 7a: Check output Avalon Stream");

      back_pressure <= '1';

      await_value(rd_en, '1', 0 ns, c_CLK_PERIOD / 10, "TEST 7a: Waiting for RAM read");
      wait_num_rising_edge(clk, 1);
      read_ram(to_unsigned(0, rd_addr'length));
      wait_num_rising_edge(clk, 1);
      rd_data <= (others => '0');
      await_value(rd_busy, '0', 0 ns, 3 * c_CLK_PERIOD, "TEST 7a: Waiting busy to fall");

      -- Double read
      start_addr <= to_unsigned(g_WORD_BYTES - 1, start_addr'length);
      rd_length  <= to_unsigned(2, rd_length'length);
      gen_pulse(rd_start, clk, 1, "TEST 7b: Start reading");

      avalon_st_expect(AVALON_ST_VVCT, 0, v_ram_bytes(g_WORD_BYTES - 1 to g_WORD_BYTES),
                       "TEST 7b: Check output Avalon Stream");

      await_value(rd_en, '1', 0 ns, c_CLK_PERIOD / 10, "TEST 7b: Waiting for RAM read");
      wait_num_rising_edge(clk, 1);
      read_ram(to_unsigned(0, rd_addr'length));
      wait_num_rising_edge(clk, 1);
      read_ram(to_unsigned(1, rd_addr'length));
      wait_num_rising_edge(clk, 1);
      rd_data <= (others => '0');

      wait_num_rising_edge(clk, 5);

      back_pressure <= '0';
      wait_num_rising_edge(clk, 1);
      back_pressure <= '1';

      -- 2-beat packet
      start_addr <= to_unsigned(g_WORD_BYTES - 1, start_addr'length);
      rd_length  <= to_unsigned(2 * g_WORD_BYTES - 1, rd_length'length);
      gen_pulse(rd_start, clk, 1, "TEST 7c: Start reading");

      avalon_st_expect(AVALON_ST_VVCT, 0, v_ram_bytes(g_WORD_BYTES - 1 to 3 * g_WORD_BYTES - 3),
                       "TEST 7c: Check output Avalon Stream");

      await_value(rd_en, '1', 0 ns, c_CLK_PERIOD / 10, "TEST 7c: Waiting for RAM read");
      wait_num_rising_edge(clk, 1);
      read_ram(to_unsigned(0, rd_addr'length));
      wait_num_rising_edge(clk, 1);
      read_ram(to_unsigned(1, rd_addr'length));
      wait_num_rising_edge(clk, 1);
      read_ram(to_unsigned(2, rd_addr'length));
      wait_num_rising_edge(clk, 1);
      rd_data <= (others => '0');

      wait_num_rising_edge(clk, 5);

      back_pressure <= '0';
      wait_num_rising_edge(clk, 1);
      back_pressure <= '1';

      wait_num_rising_edge(clk, 5);
      back_pressure <= '0';
      wait_num_rising_edge(clk, 2);
      back_pressure <= '1';

      check_value(rd_busy, '0', "TEST 7c: Component should cease to be busy");

      -- 3-beat packet
      start_addr <= to_unsigned(g_WORD_BYTES + 1, start_addr'length);
      rd_length  <= to_unsigned(3 * g_WORD_BYTES - 2, rd_length'length);
      gen_pulse(rd_start, clk, 1, "TEST 7d: Start reading");

      avalon_st_expect(AVALON_ST_VVCT, 0, v_ram_bytes(g_WORD_BYTES + 1 to 4 * g_WORD_BYTES - 2),
                       "TEST 7d: Check output Avalon Stream");

      await_value(rd_en, '1', 0 ns, c_CLK_PERIOD / 10, "TEST 7d: Waiting for RAM read");
      wait_num_rising_edge(clk, 1);
      read_ram(to_unsigned(1, rd_addr'length));
      wait_num_rising_edge(clk, 1);
      read_ram(to_unsigned(2, rd_addr'length));
      wait_num_rising_edge(clk, 1);
      read_ram(to_unsigned(3, rd_addr'length));
      wait_num_rising_edge(clk, 1);
      rd_data <= (others => '0');

      wait_num_rising_edge(clk, 5);
      back_pressure <= '0';

      await_completion(AVALON_ST_VVCT, 0, 1 ms, "Waiting for Avalon output to finish");
    end if;

    ------------------------- VUNIT CLEANUP --------------------------
    test_runner_cleanup(runner);

  end process proc_verify;

  test_runner_watchdog(runner, 100 us);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
