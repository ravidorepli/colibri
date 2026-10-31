-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;

library vunit_lib;
  context vunit_lib.vunit_context;

library osvvm;
  context osvvm.osvvmcontext;

----------------------------------------------------------------------------------------------------

entity synchro_pulse_tb is
  generic (
    RUNNER_CFG       : string;
    --! Destination and source domain clock periods
    g_DST_CLK_PERIOD : time     := 50 ns;
    g_SRC_CLK_PERIOD : time     := 5 ns;
    --! Number of FF synchronization stages
    g_NUM_STAGES     : positive := 2
  );
end entity synchro_pulse_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of synchro_pulse_tb is

  --! Double ratio between destination and source clock periods
  constant c_CLOCK_RATIO_X2  : positive := div_ceil(2 * g_DST_CLK_PERIOD, g_SRC_CLK_PERIOD);
  --! Number of consecutive pulses to test
  constant c_NUM_CONS_PULSES : positive := 100;

  --! UUT signals
  signal src_clk   : std_logic := '1';
  signal dst_clk   : std_logic := '1';
  signal pulse_in  : std_logic := '0';
  signal pulse_out : std_logic;

  --! Procedure to wait for a number of clock cycles and some time after

  procedure wait_clk_cycles_and_after (
    signal clk          : in std_logic;
    constant c_n_cycles : positive;
    constant c_after    : time
  ) is
  begin

    osvvm.TbUtilPkg.WaitForClock(clk, c_n_cycles);
    wait for c_after;

  end procedure wait_clk_cycles_and_after;

begin

  -- Generate clock and reset
  osvvm.TbUtilPkg.CreateClock(src_clk, g_SRC_CLK_PERIOD);
  osvvm.TbUtilPkg.CreateClock(dst_clk, g_DST_CLK_PERIOD);

  ------------------------------------------------------------------------------
  --! Unit under test
  ------------------------------------------------------------------------------
  u_synchro_pulse : entity colibri.synchro_pulse
    generic map (
      g_NUM_STAGES => g_NUM_STAGES
    )
    port map (
      src_clk_i => src_clk,
      dst_clk_i => dst_clk,
      pulse_i   => pulse_in,
      pulse_o   => pulse_out
    );

  ------------------------------------------------------------------------------
  --! Input generation
  ------------------------------------------------------------------------------
  proc_input : process is
  begin

    -- TEST 2: Generate a single pulse -----------------------------------------
    osvvm.TbUtilPkg.WaitForClock(dst_clk);
    osvvm.TbUtilPkg.WaitForClock(src_clk);
    pulse_in <= '1';
    osvvm.TbUtilPkg.WaitForClock(src_clk);
    pulse_in <= '0';
    wait until falling_edge(pulse_out);

    -- TEST 3: Generate consecutive pulses with max frequency ------------------
    for i in 1 to c_NUM_CONS_PULSES loop
      osvvm.TbUtilPkg.WaitForClock(src_clk, maximum(c_CLOCK_RATIO_X2 - 1, 1));
      pulse_in <= '1';
      osvvm.TbUtilPkg.WaitForClock(src_clk);
      pulse_in <= '0';
    end loop;

    -- TEST 4: Generate a wider pulse ------------------------------------------
    osvvm.TbUtilPkg.WaitForClock(src_clk, g_NUM_STAGES * c_CLOCK_RATIO_X2);
    pulse_in <= '1';
    osvvm.TbUtilPkg.WaitForClock(src_clk, 5 * maximum(g_DST_CLK_PERIOD, g_SRC_CLK_PERIOD));
    pulse_in <= '0';

    wait;

  end process proc_input;

  ------------------------------------------------------------------------------
  --! Verification process (VUnit)
  ------------------------------------------------------------------------------
  proc_vunit : process is
  begin

    ------------------------------- VUNIT SETUP --------------------------------
    test_runner_setup(runner, RUNNER_CFG);

    -- TEST 1: Module is initialized without a reset signal --------------------
    wait until rising_edge(dst_clk);
    check(pulse_out = '0', "Output not initialized immediately.");

    -- TEST 2: Single pulse propagation ----------------------------------------
    wait until rising_edge(pulse_in);
    osvvm.TbUtilPkg.WaitForClock(dst_clk, g_NUM_STAGES);
    wait until pulse_out = '1' for 2 * maximum(g_DST_CLK_PERIOD, g_SRC_CLK_PERIOD);
    check(pulse_out = '1', "Single pulse did not propagate.");
    wait_clk_cycles_and_after(dst_clk, 1, g_DST_CLK_PERIOD / 10);
    check(pulse_out = '0', "Destination pulse lasted longer than 1 cycle.");

    -- TEST 3: Consecutive pulse propagation with max frequency ----------------
    wait until rising_edge(pulse_in);
    osvvm.TbUtilPkg.WaitForClock(dst_clk, g_NUM_STAGES);

    for i in 1 to c_NUM_CONS_PULSES loop
      wait until pulse_out = '1' for 2 * maximum(g_DST_CLK_PERIOD, g_SRC_CLK_PERIOD);
      check(pulse_out = '1',
            "Consecutive pulse no." & to_string(i) & " did not propagate within 2 CC.");
      wait_clk_cycles_and_after(dst_clk, 1, g_DST_CLK_PERIOD / 10);
      check(pulse_out = '0',
            "Destination pulse no." & to_string(i) & " lasted longer than 1 cycle.");
    end loop;

    -- TEST 4: Wider source pulse should produce a single dest. pulse ----------
    wait until pulse_out = '1' for 100 * g_NUM_STAGES * g_DST_CLK_PERIOD;
    check(pulse_out = '1', "Wider pulse did not propagate!");
    wait_clk_cycles_and_after(dst_clk, 1, g_DST_CLK_PERIOD / 10);
    check(pulse_out = '0', "Wider pulse response lasted longer than 1 cycle.");

    -- TEST 5: Make sure there are no unexpected pulses generated in the end ---
    wait until pulse_out = '1' for 100 * g_NUM_STAGES * g_DST_CLK_PERIOD;
    check(pulse_out = '0', "Unexpected pulse generated on the output!");

    ------------------------------ VUNIT CLEANUP -------------------------------
    test_runner_cleanup(runner);

  end process proc_vunit;

  test_runner_watchdog(runner, 1 ms);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
