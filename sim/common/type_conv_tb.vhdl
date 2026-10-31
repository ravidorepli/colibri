-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.types.all;

library vunit_lib;
  context vunit_lib.vunit_context;

library osvvm;
  context osvvm.osvvmcontext;

----------------------------------------------------------------------------------------------------

entity type_conv_tb is
  generic (
    g_CLK_PERIOD : time    := 10 ns;
    g_ELEM_SIZE  : natural := 16;

    RUNNER_CFG : string
  );
end entity type_conv_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of type_conv_tb is

  constant c_INIT_ARRAY : int_array_t := (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12);

  signal clk : std_logic;

  signal uns_array : uns_array_t(c_INIT_ARRAY'range)(g_ELEM_SIZE - 1 downto 0)        := (others => (others => '0'));
  signal slv_array : slv_array_t(c_INIT_ARRAY'range)(g_ELEM_SIZE - 1 downto 0)        := (others => (others => '0'));
  signal slv       : std_logic_vector(c_INIT_ARRAY'length * g_ELEM_SIZE - 1 downto 0) := (others => '0');
  signal int_array : int_array_t(c_INIT_ARRAY'range)                                  := (others => 0);

begin

  -- Generate clock and reset
  osvvm.TbUtilPkg.CreateClock(clk, g_CLK_PERIOD);

  ----------------------------------------------------------------------------
  --! Verification process (VUnit)
  ----------------------------------------------------------------------------
  proc_vunit : process is
  begin

    ------------ VUNIT SETUP ------------
    test_runner_setup(runner, RUNNER_CFG);

    wait until rising_edge(clk);
    uns_array <= int_array_to_uns_array(c_INIT_ARRAY, g_ELEM_SIZE);
    wait until rising_edge(clk);
    slv       <= uns_array_to_slv(uns_array, g_ELEM_SIZE);
    wait until rising_edge(clk);
    slv_array <= slv_to_slv_array(slv, g_ELEM_SIZE);
    wait until rising_edge(clk);
    slv       <= slv_array_to_slv(slv_array, g_ELEM_SIZE);
    wait until rising_edge(clk);
    uns_array <= slv_to_uns_array(slv, g_ELEM_SIZE);
    wait until rising_edge(clk);
    int_array <= uns_array_to_int_array(uns_array);

    wait until rising_edge(clk);

    for i in c_INIT_ARRAY'range loop
      check(int_array(i) = c_INIT_ARRAY(i), "Check that the values propagated unchanged.");
    end loop;

    osvvm.TbUtilPkg.WaitForClock(clk, 3);

    ----------- VUNIT CLEANUP -----------
    test_runner_cleanup(runner);

  end process proc_vunit;

  test_runner_watchdog(runner, 10 ms);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
