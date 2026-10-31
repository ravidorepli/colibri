-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library vunit_lib;
  context vunit_lib.vunit_context;

library osvvm;
  use osvvm.randompkg.all;

library colibri;
  use colibri.utils.all;
  use colibri.poly.all;

entity prbs_tb is
  generic (

    RUNNER_CFG : string
  );
end entity prbs_tb;

architecture sim of prbs_tb is

  shared variable v_rv         : RandomPType;
  constant        c_CLK_PERIOD : time                                        := 10 ns;
  constant        c_DATA_WIDTH : natural                                     := 32;
  constant        c_SIGNATURE  : std_logic_vector(c_DATA_WIDTH - 1 downto 0) := 32x"deadbeef";

  signal clk                : std_logic := '1';
  signal reset              : std_logic := '1';
  signal snk_data, src_data : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal scrambled_data     : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal valid_sig          : std_logic;
  signal snk_valid          : std_logic;
  signal src_valid          : std_logic;
  signal ready_sig          : std_logic;
  signal src_ready          : std_logic;

begin

  clk <= not clk after c_CLK_PERIOD / 2;

  scrambler_vhdl_inst : entity colibri.scrambler(rtl)
    generic
    map (
      g_DATA_WIDTH     => c_DATA_WIDTH,
      g_SCRAMBLER_POLY => c_PRBS_7,
      g_INIT_VAL       => 8x"a4"
    )
    port map (
      clk_i       => clk,
      reset_i     => reset,
      snk_data_i  => snk_data,
      snk_valid_i => snk_valid,
      snk_ready_o => open,
      src_data_o  => scrambled_data,
      src_valid_o => valid_sig,
      src_ready_i => ready_sig
    );

  descrambler_vhdl_inst : entity colibri.descrambler(rtl)
    generic
    map (
      g_DATA_WIDTH     => c_DATA_WIDTH,
      g_SCRAMBLER_POLY => c_PRBS_7,
      g_INIT_VAL       => 8x"a4"

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
      src_ready_i => src_ready
    );

  proc_checker : process is
  begin

    if (src_valid = '1') then
      check(src_data = c_SIGNATURE, result("c_SIGNATURE mismatch"));
    end if;

    wait for c_CLK_PERIOD;

  end process proc_checker;

  proc_ready_trigger : process is
  begin

    src_ready <= v_rv.RandSlv(1)(1);
    snk_valid <= v_rv.RandSlv(1)(1);
    wait until rising_edge(clk);

  end process proc_ready_trigger;

  proc_sequencer : process is
  begin

    ---------------- VUNIT SETUP ---------------
    test_runner_setup(runner, RUNNER_CFG);

    -- TEST : normal behaviour
    if run("prbs") then
      wait for c_CLK_PERIOD;
      reset    <= '0';
      snk_data <= c_SIGNATURE;
      wait for 100 * c_CLK_PERIOD;
    end if;

    -- VUnit cleanup
    test_runner_cleanup(runner);

  end process proc_sequencer;

end architecture sim;
