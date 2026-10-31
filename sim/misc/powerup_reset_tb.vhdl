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

entity powerup_reset_tb is
  generic (
    g_CLK_PERIOD : time      := 10 ns;
    g_POLARITY   : std_logic := '1'; --! Output signal polarity ('1' = active high)
    g_DURATION   : positive  := 10;  --! Output signal duration
    RUNNER_CFG   : string
  );
end entity powerup_reset_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of powerup_reset_tb is

  -- powerup_reset ports
  signal clk_i       : std_logic := '1';
  signal reset_ext_i : std_logic := '0';
  signal reset_o     : std_logic;

begin

  -- Generate clock
  osvvm.TbUtilPkg.CreateClock(clk_i, g_CLK_PERIOD);

  ----------------------------------------------------------------------------
  --! Unit under test
  ----------------------------------------------------------------------------
  u_poweruprst : entity colibri.powerup_reset
    generic map (
      g_POLARITY => g_POLARITY,
      g_DURATION => g_DURATION
    )
    port map (
      clk_i       => clk_i,
      reset_ext_i => reset_ext_i,
      reset_o     => reset_o
    );

  ----------------------------------------------------------------------------
  --! Verification process (VUnit)
  ----------------------------------------------------------------------------
  proc_vunit : process is
  begin

    ------------ VUNIT SETUP ------------
    test_runner_setup(runner, RUNNER_CFG);

    -- Check initial reset assertion
    check(reset_o = g_POLARITY, "Check that the reset output is activated correctly.");
    osvvm.TbUtilPkg.WaitForClock(clk_i, g_DURATION * g_CLK_PERIOD);
    wait for g_CLK_PERIOD / 10;
    check(reset_o = not g_POLARITY, "Check that the reset output is deactivated after the set period.");
    osvvm.TbUtilPkg.WaitForClock(clk_i, 1 us);

    -- Check assertion upon external reset
    reset_ext_i <= '1';
    wait for g_CLK_PERIOD / 10;
    check(reset_o = g_POLARITY, "Check that the reset output is activated after an external reset.");
    osvvm.TbUtilPkg.WaitForClock(clk_i, 3 * g_CLK_PERIOD);
    reset_ext_i <= '0';
    check(reset_o = g_POLARITY, "Check that the reset output stays active after an external reset.");

    -- Check deassertion after external reset
    osvvm.TbUtilPkg.WaitForClock(clk_i, g_DURATION * g_CLK_PERIOD);
    wait for g_CLK_PERIOD / 10;
    check(reset_o = not g_POLARITY, "Check that the reset output is deactivated after the set period.");

    ----------- VUNIT CLEANUP -----------
    test_runner_cleanup(runner);

  end process proc_vunit;

  test_runner_watchdog(runner, 10 ms);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
