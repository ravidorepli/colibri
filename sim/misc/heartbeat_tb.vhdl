-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;

library vunit_lib;
  context vunit_lib.vunit_context;

library osvvm;
  context osvvm.osvvmcontext;

----------------------------------------------------------------------------------------------------

entity heartbeat_tb is
  generic (
    g_CLK_PERIOD  : time := 10 ns;
    g_BEAT_PERIOD : time := 100 ns;
    RUNNER_CFG    : string
  );
end entity heartbeat_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of heartbeat_tb is

  -- Heartbeat ports
  signal clk_i       : std_logic := '1';
  signal reset_i     : std_logic := '1';
  signal heartbeat_o : std_logic;

begin

  -- Generate clock and reset
  osvvm.TbUtilPkg.CreateClock(clk_i, g_CLK_PERIOD);
  osvvm.TbUtilPkg.CreateReset(reset_i, '1', clk_i, g_BEAT_PERIOD, 0 ns);

  ----------------------------------------------------------------------------
  --! Unit under test
  ----------------------------------------------------------------------------
  u_heartbeat : entity colibri.heartbeat
    generic map (
      g_BEAT_PERIOD => g_BEAT_PERIOD,
      g_CLK_PERIOD  => g_CLK_PERIOD
    )
    port map (
      clk_i       => clk_i,
      reset_i     => reset_i,
      heartbeat_o => heartbeat_o
    );

  ----------------------------------------------------------------------------
  --! Verification process (VUnit)
  ----------------------------------------------------------------------------
  proc_vunit : process is
  begin

    ------------ VUNIT SETUP ------------
    test_runner_setup(runner, RUNNER_CFG);

    wait until reset_i = '0' and rising_edge(clk_i);
    check(heartbeat_o = '0', "Check that the output is initialized to 0.");

    for i in 0 to 100 loop
      osvvm.TbUtilPkg.WaitForClock(clk_i, g_BEAT_PERIOD / 2);
      check(heartbeat_o = '1', "Check that the output transitions after half period.");
      osvvm.TbUtilPkg.WaitForClock(clk_i, g_BEAT_PERIOD / 2);
      check(heartbeat_o = '0', "Check that the output transitions after half period.");
    end loop;

    ----------- VUNIT CLEANUP -----------
    test_runner_cleanup(runner);

  end process proc_vunit;

  test_runner_watchdog(runner, 10 ms);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
