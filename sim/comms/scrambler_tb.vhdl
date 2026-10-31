-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library vunit_lib;
  context vunit_lib.vunit_context;

library colibri;
  use colibri.utils.all;

entity scrambler_tb is
  generic (

    RUNNER_CFG : string
  );
end entity scrambler_tb;

architecture sim of scrambler_tb is

  constant c_CLK_PERIOD : time                                        := 10 ns;
  constant c_DATA_WIDTH : natural                                     := 64;
  constant c_WORD       : std_logic_vector(c_DATA_WIDTH - 1 downto 0) := 64x"A0750F3BF76980F6";

  signal clk                : std_logic := '1';
  signal reset              : std_logic := '1';
  signal snk_data, src_data : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal scrambled_data     : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal valid_sig          : std_logic;
  signal src_valid          : std_logic;
  signal ready_sig          : std_logic;

begin

  clk <= not clk after c_CLK_PERIOD / 2;

  scrambler_vhdl_inst : entity colibri.scrambler(rtl)
    generic
    map (
      g_DATA_WIDTH => 64
    )
    port map (
      clk_i       => clk,
      reset_i     => reset,
      snk_data_i  => snk_data,
      snk_valid_i => '1',
      snk_ready_o => open,
      src_data_o  => scrambled_data,
      src_valid_o => valid_sig,
      src_ready_i => ready_sig
    );

  descrambler_vhdl_inst : entity colibri.descrambler(rtl)
    generic
    map (
      g_DATA_WIDTH => 64
    )
    port
    map (
      clk_i       => clk,
      reset_i     => reset,
      snk_data_i  => scrambled_data,
      snk_valid_i => valid_sig,
      snk_ready_o => ready_sig,
      src_data_o  => src_data,
      src_valid_o => src_valid,
      src_ready_i => '1'
    );

  proc_checker : process is
  begin

    if (src_valid = '1') then
      check(src_data = c_WORD, result("c_word mismatch"));
    end if;

    wait for c_CLK_PERIOD;

  end process proc_checker;

  proc_sequencer : process is
  begin

    ---------------- VUNIT SETUP ---------------
    test_runner_setup(runner, RUNNER_CFG);

    -- TEST : normal behaviour
    if run("scrambler") then
      wait for c_CLK_PERIOD;
      reset    <= '0';
      snk_data <= 64x"0";
      snk_data <= c_WORD;
      wait for 40 * c_CLK_PERIOD;
    end if;

    -- VUnit cleanup
    test_runner_cleanup(runner);

  end process proc_sequencer;

end architecture sim;
