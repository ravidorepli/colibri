
--==================================================================================================
--! @brief Simple Comparator TB
--! @file comparator_tb.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 26-09-2025 Created
--! @version 0.1
--! @copyright CERN 2025
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;

library osvvm;
  context osvvm.osvvmcontext;
  use osvvm.randompkg.all;
  use osvvm.coveragepkg.all;

--
library vunit_lib;
  context vunit_lib.vunit_context;

-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

entity comparator_tb is
  generic (
    RUNNER_CFG : string
  );
end entity comparator_tb;

architecture bench of comparator_tb is

  -- Clock period
  constant c_CLK_PERIOD : time := 5 ns;
  constant c_IS_EQUAL : boolean := true;
  -- Generics
  constant c_DATA_WIDTH : positive := 12;
  -- Ports
  signal clk            : std_logic := '1';
  signal enable         : std_logic := '0';
  signal input          : unsigned(c_DATA_WIDTH - 1 downto 0);
  signal thres          : unsigned(c_DATA_WIDTH - 1 downto 0);
  signal trigger        : std_logic;
  -- OSVVM coverage
  shared variable v_rv  : randomptype;
  signal          s_cov : coverageidtype;

begin

  comparator_inst : entity colibri.comparator
    generic map (
      g_DATA_WIDTH => c_DATA_WIDTH,
      g_IS_EQUAL   => c_IS_EQUAL
    )
    port map (
      clk_i    => clk,
      enable_i => enable,
      a_i      => input,
      b_i      => thres,
      a_gt_b_o => trigger
    );

  proc_seq : process is
  begin

    test_runner_setup(runner, RUNNER_CFG);
    s_cov <= NewID("valid coverage");
    osvvm.TbUtilPkg.WaitForClock(clk, 1);
    addBins(s_cov, "Enabled Compare True", 10, GenBin(0));
    addBins(s_cov, "Enabled Compare False", 10, GenBin(1));
    addBins(s_cov, "Check Equal", 10, GenBin(2));
    addBins(s_cov, "Disabled", 10, GenBin(3));

    while not IsCovered(s_cov) loop
      osvvm.TbUtilPkg.WaitForClock(clk, 1);
    end loop;

    writebin(s_cov);
    test_runner_cleanup(runner);

  end process proc_seq;

  proc_cover : process is

    variable v_t : natural;
    variable v_i : natural;

  begin

    osvvm.TbUtilPkg.WaitForClock(clk, 10);

    while not IsCovered(s_cov) loop
      v_t   := v_rv.RandInt(2 ** c_DATA_WIDTH - 1);
      v_i   := v_rv.RandInt(2 ** c_DATA_WIDTH - 1);
      input <= TO_UNSIGNED(v_i, c_DATA_WIDTH);
      thres <= TO_UNSIGNED(v_t, c_DATA_WIDTH);

      if (v_rv.RandSlv(1)(1)) then
        enable <= '1';
        osvvm.TbUtilPkg.WaitForClock(clk, 1);
        wait for 1 ns;
        if (v_i > v_t) then
          check(trigger = '1', "GT trigger not fired");
          ICover(s_cov, 0);
        elsif (v_i = v_t) then
          check(trigger = '1' xnor c_IS_EQUAL, "Equal trigger not fired");
          ICover(s_cov, 2);
        else
          check(trigger = '0', "Fired when LT");
          ICover(s_cov, 1);
        end if;
      else
        enable <= '0';
        osvvm.TbUtilPkg.WaitForClock(clk, 1);
        check(trigger = '0', "Fired when Disabled");
        ICover(s_cov, 3);
      end if;

      enable <= '0';
      osvvm.TbUtilPkg.WaitForClock(clk, 1);
    end loop;

  end process proc_cover;

  osvvm.TbUtilPkg.CreateClock(clk, c_CLK_PERIOD);

end architecture bench;
