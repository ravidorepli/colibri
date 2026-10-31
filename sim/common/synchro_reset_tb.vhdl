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

entity synchro_reset_tb is
  generic (
    g_CLK_PERIOD : time := 10 ns;

    g_IN_POLARITY  : std_logic := '1';
    g_OUT_POLARITY : std_logic := '1';
    g_DURATION     : positive  := 1;

    RUNNER_CFG : string
  );
end entity synchro_reset_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of synchro_reset_tb is

  signal clk_i   : std_logic;
  signal reset_i : std_logic := not g_IN_POLARITY;
  signal reset_o : std_logic;

begin

  -- Generate clock and reset
  osvvm.TbUtilPkg.CreateClock(clk_i, g_CLK_PERIOD);

  ----------------------------------------------------------------------------
  --! Unit under test
  ----------------------------------------------------------------------------
  u_synchro_reset : entity colibri.synchro_reset
    generic map (
      g_IN_POLARITY  => g_IN_POLARITY,
      g_OUT_POLARITY => g_OUT_POLARITY,
      g_DURATION     => g_DURATION
    )
    port map (
      clk_i   => clk_i,
      reset_i => reset_i,
      reset_o => reset_o
    );

  ----------------------------------------------------------------------------
  --! Verification process (VUnit)
  ----------------------------------------------------------------------------
  proc_vunit : process is
  begin

    ------------ VUNIT SETUP ------------
    test_runner_setup(runner, RUNNER_CFG);

    -- TEST: Module is initialized correctly
    wait until rising_edge(clk_i);
    check(reset_o = not g_OUT_POLARITY, "Check that the RESET is initialized correctly.");
    osvvm.TbUtilPkg.WaitForClock(clk_i, 3);

    -- TEST: Reset is asserted asynchronously
    wait for g_CLK_PERIOD / 4;
    reset_i <= g_IN_POLARITY;
    wait for g_CLK_PERIOD / 4;
    check(reset_o = g_OUT_POLARITY, "Check that reset is asserted asynchronously.");
    wait for g_CLK_PERIOD / 4;
    reset_i <= not g_IN_POLARITY;

    -- TEST: Reset is asserted for g_DURATION clock cycles
    wait until rising_edge(clk_i);

    if (g_DURATION > 1) then
      osvvm.TbUtilPkg.WaitForClock(clk_i, g_DURATION - 1);
    end if;

    check(reset_o = g_OUT_POLARITY, "Check that the reset is kept for g_DURATION CCs.");
    wait until rising_edge(clk_i);
    wait for g_CLK_PERIOD / 4;
    check(reset_o = not g_OUT_POLARITY, "Check that the reset is de-asserted after g_DURATION CCs.");

    ----------- VUNIT CLEANUP -----------
    test_runner_cleanup(runner);

  end process proc_vunit;

  test_runner_watchdog(runner, 10 ms);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
