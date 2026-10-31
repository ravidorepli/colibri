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

entity bit_shifter_tb is
  generic (
    RUNNER_CFG   : string;
    g_DATA_WIDTH : positive; --! Input word width in terms of bits
    g_MSB_RIGHT  : boolean   --! Orientation of the input words
  );
end entity bit_shifter_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of bit_shifter_tb is

  constant c_CLK_PERIOD : time := 10 ns;

  -- bit_shifter ports
  signal clk      : std_logic                                     := '1';
  signal reset    : std_logic                                     := '1';
  signal offset_i : unsigned(log2ceil(g_DATA_WIDTH) - 1 downto 0) := (others => '0');
  signal data_i   : std_logic_vector(g_DATA_WIDTH - 1 downto 0)   := (others => '0');
  signal data_o   : std_logic_vector(g_DATA_WIDTH - 1 downto 0);

begin

  -- Generate clock and reset
  osvvm.TbUtilPkg.CreateClock(clk, c_CLK_PERIOD);
  osvvm.TbUtilPkg.CreateReset(reset, '1', clk, c_CLK_PERIOD, 0 ns);

  ----------------------------------------------------------------------------
  --! Unit under test
  ----------------------------------------------------------------------------
  u_bit_shifter : entity colibri.bit_shifter
    generic map (
      g_DATA_WIDTH => g_DATA_WIDTH,
      g_MSB_RIGHT  => g_MSB_RIGHT
    )
    port map (
      clk_i    => clk,
      reset_i  => reset,
      offset_i => offset_i,
      data_i   => data_i,
      data_o   => data_o
    );

  ------------------------------------------------------------------------------
  --! Verification process (VUnit)
  ------------------------------------------------------------------------------
  proc_stimulation : process is
  begin

    ------------------------------- VUNIT SETUP --------------------------------
    test_runner_setup(runner, RUNNER_CFG);

    wait until reset = '0' and rising_edge(clk);

    -- Check that data propagates in one clock cycle unchanged -----------------
    data_i <= std_logic_vector(to_unsigned(10, g_DATA_WIDTH));
    osvvm.TbUtilPkg.WaitForClock(clk);
    wait for c_CLK_PERIOD / 10;
    check(data_o = std_logic_vector(to_unsigned(10, g_DATA_WIDTH)),
          "Data did not propagate in 1 clock cycle!");

    -- Check that data keeps propagating unchanged -----------------------------
    osvvm.TbUtilPkg.WaitForClock(clk, 5);
    check(data_o = std_logic_vector(to_unsigned(10, g_DATA_WIDTH)),
          "Output did not persist!");

    -- Check that data gets shifted correctly ----------------------------------
    data_i                    <= (others => '0');
    data_i(data_i'length / 2) <= '1';

    for off in 1 to data_i'left / 2 loop
      offset_i <= to_unsigned(off, offset_i'length);
      osvvm.TbUtilPkg.WaitForClock(clk);
      wait for c_CLK_PERIOD / 10;

      if (g_MSB_RIGHT) then
        check(data_o = data_i sll off, "Data did not shift correctly!");
      else
        check(data_o = data_i srl off, "Data did not shift correctly!");
      end if;

    end loop;

    -- Check that data keeps propagating unchanged -----------------------------
    osvvm.TbUtilPkg.WaitForClock(clk, 5);

    if (g_MSB_RIGHT) then
      check(data_o = data_i sll data_i'left / 2, "Output did not persist after shift!");
    else
      check(data_o = data_i srl data_i'left / 2, "Output did not persist after shift!");
    end if;

    -- Check that bits get shifted between words--------------------------------
    for off in data_i'left / 2 + 2 to data_i'left loop
      offset_i <= to_unsigned(off, offset_i'length);
      osvvm.TbUtilPkg.WaitForClock(clk);
      wait for c_CLK_PERIOD / 10;

      if (g_MSB_RIGHT) then
        check(data_o = data_i srl data_i'length - off,
              "Data did not shift correctly accross the word edge!");
      else
        check(data_o = data_i sll data_i'length - off,
              "Data did not shift correctly accross the word edge!");
      end if;

    end loop;

    osvvm.TbUtilPkg.WaitForClock(clk, 5);
    ------------------------------ VUNIT CLEANUP -------------------------------
    test_runner_cleanup(runner);

  end process proc_stimulation;

end architecture behavioural;

----------------------------------------------------------------------------------------------------
