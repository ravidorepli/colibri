--==================================================================================================
--! @brief Frequency Counter TB
--! @file frequency_counter_tb.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 05-01-2025 Created
--! @version 0.1
--! @copyright CERN 2025
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  context colibri.common;

--
library vunit_lib;
  context vunit_lib.vunit_context;

library osvvm;
  context osvvm.osvvmcontext;

-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

entity frequency_counter_tb is
  generic (
    RUNNER_CFG : string
  );
end entity frequency_counter_tb;

architecture bench of frequency_counter_tb is

  -- Clock period
  constant c_CLK_REF_PERIOD  : time := 10 ns;
  constant c_CLK_A_PERIOD    : time := 25 ns;
  constant c_CLK_B_PERIOD    : time := 4.158 ns;
  -- Generics
  constant c_CLK_REF_FREQ_HZ : positive := 1 sec / c_CLK_REF_PERIOD;
  constant c_NUM_CLOCKS      : positive := 2;
  constant c_DATA_WIDTH      : positive := 32;
  constant c_SAMPLE_FREQ_HZ  : positive := 1000;
  -- Ports
  signal clk_ref             : std_logic := '1';
  signal reset               : std_logic := '1';
  signal clk_a               : std_logic := '1';
  signal clk_b               : std_logic := '1';
  signal clk_meas            : std_logic_vector(c_NUM_CLOCKS - 1 downto 0);
  signal freq_data           : uns_array_t(0 to c_NUM_CLOCKS - 1)(c_DATA_WIDTH - 1 downto 0);
  signal freq_valid          : std_logic_vector(c_NUM_CLOCKS - 1 downto 0);

  -- clock freqs
  constant c_CLK_A_FREQ : positive := 1 sec / c_CLK_A_PERIOD;
  constant c_CLK_B_FREQ : positive := 1 sec / c_CLK_B_PERIOD;

  signal done : std_logic;

  constant c_THRES : natural := 4;

  constant c_CLK_A_UNCERTAINTY : natural := div_ceil(c_CLK_A_FREQ, c_CLK_REF_FREQ_HZ) * c_SAMPLE_FREQ_HZ;
  constant c_CLK_B_UNCERTAINTY : natural := div_ceil(c_CLK_B_FREQ, c_CLK_REF_FREQ_HZ) * c_SAMPLE_FREQ_HZ;
  signal   count_a             : natural := 0;
  signal   count_b             : natural := 0;

begin

  frequency_counter_inst : entity colibri.frequency_counter
    generic map (
      g_CLK_REF_FREQ_HZ => c_CLK_REF_FREQ_HZ,
      g_NUM_CLOCKS      => c_NUM_CLOCKS,
      g_DATA_WIDTH      => c_DATA_WIDTH,
      g_SAMPLE_FREQ_HZ  => c_SAMPLE_FREQ_HZ
    )
    port map (
      clk_ref_i    => clk_ref,
      reset_i      => reset,
      clk_meas_i   => clk_meas,
      freq_data_o  => freq_data,
      freq_valid_o => freq_valid
    );

  osvvm.TbUtilPkg.CreateClock(clk_ref, c_CLK_REF_PERIOD);
  osvvm.TbUtilPkg.CreateClock(clk_a, c_CLK_A_PERIOD);
  osvvm.TbUtilPkg.CreateClock(clk_b, c_CLK_B_PERIOD);
  osvvm.TbUtilPkg.CreateReset(reset, '1', clk_ref, c_CLK_REF_PERIOD * 2, 0 ns);
  clk_meas <= clk_b & clk_a;

  proc_main : process is
  begin

    test_runner_setup(runner, RUNNER_CFG);
    osvvm.TbUtilPkg.WaitForLevel(reset, '0');
    info("Reset released");
    osvvm.TbUtilPkg.WaitForLevel(done, '1');
    test_runner_cleanup(runner);

  end process proc_main;

  test_runner_watchdog(runner, 10 ms);

  proc_clk_a : process is
  begin

    osvvm.TbUtilPkg.WaitForLevel(freq_valid(0));
    wait for 0 ns;

    if (count_a > 0) then
      check(freq_data(0) <= c_CLK_A_FREQ + c_CLK_A_UNCERTAINTY, "CLK A freq too high! expected "&to_string(c_CLK_A_FREQ) & " uncertainty "& to_string(c_CLK_A_UNCERTAINTY));
      check(freq_data(0) >= c_CLK_A_FREQ - c_CLK_A_UNCERTAINTY, "CLK A freq too low! expected "&to_string(c_CLK_A_FREQ) & " uncertainty "& to_string(c_CLK_A_UNCERTAINTY));
    end if;

    count_a <= count_a + 1;
    osvvm.TbUtilPkg.WaitForClock(clk_ref, 10);

  end process proc_clk_a;

  proc_clk_b : process is
  begin

    osvvm.TbUtilPkg.WaitForLevel(freq_valid(1));
    wait for 0 ns;

    if (count_b > 0) then
      check(freq_data(1) <= c_CLK_B_FREQ + c_CLK_B_UNCERTAINTY, "CLK B freq too high! expected "&to_string(c_CLK_B_FREQ)& " uncertainty "& to_string(c_CLK_B_UNCERTAINTY));
      check(freq_data(1) >= c_CLK_B_FREQ - c_CLK_B_UNCERTAINTY, "CLK B freq too low! expected "&to_string(c_CLK_B_FREQ)& " uncertainty "& to_string(c_CLK_B_UNCERTAINTY));
    end if;

    count_b <= count_b + 1;
    osvvm.TbUtilPkg.WaitForClock(clk_ref, 10);

  end process proc_clk_b;

  done <= '1' when count_a > c_THRES and count_b > c_THRES else
          '0';
-- clk <= not clk after clk_period/2;

end architecture bench;
