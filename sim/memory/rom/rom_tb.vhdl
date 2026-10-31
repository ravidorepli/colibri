-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

use std.textio.all;

library colibri;
  context colibri.common;

library vunit_lib;
  context vunit_lib.vunit_context;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

----------------------------------------------------------------------------------------------------

entity rom_tb is
  generic (
    RUNNER_CFG : string;

    --! Number of words to store
    g_N_WORDS    : positive := 20;
    --! Word size in bits
    g_DATA_WIDTH : positive := 32
  );
end entity rom_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of rom_tb is

  --! Content initialization file path
  constant c_INIT_FILE : string := "sim/memory/rom/rom_contents.txt";

  --! Clock period
  constant c_CLK_PERIOD : time := 10 ns;

  --! UUT interface signals
  signal clk  : std_logic;
  signal addr : unsigned(log2ceil(g_N_WORDS) - 1 downto 0);
  signal data : std_logic_vector(g_DATA_WIDTH - 1 downto 0);

--------------------------------------------------------------------------------

begin ----------------------------------------------------------------------------------------------

  -- Generate clocks
  clock_generator(clk, c_CLK_PERIOD);

  ------------------------------------------------------------------------------
  --! Unit under test
  ------------------------------------------------------------------------------
  uut_rom : entity colibri.rom
    generic map (
      g_N_WORDS    => g_N_WORDS,
      g_DATA_WIDTH => g_DATA_WIDTH,
      g_INIT_FILE  => c_INIT_FILE
    )
    port map (
      clk_i  => clk,
      addr_i => addr,
      data_o => data
    );

  ------------------------------------------------------------------------------
  --! VUnit verification process
  ------------------------------------------------------------------------------
  proc_verify : process is

    file     rom_file : text open read_mode is c_INIT_FILE;
    variable v_row    : line;
    variable v_data   : data'subtype;

  begin

    -------------------------- VUNIT SETUP --------------------------
    test_runner_setup(runner, RUNNER_CFG);

    for i in 0 to g_N_WORDS - 1 loop
      addr <= to_unsigned(i, addr'length);

      wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
      readline(rom_file, v_row);
      hread(v_row, v_data);
      check_value(data, v_data, "Testing data at address " & to_string(i));
    end loop;

    ------------------------- VUNIT CLEANUP --------------------------
    test_runner_cleanup(runner);

  end process proc_verify;

end architecture behavioural;

----------------------------------------------------------------------------------------------------
