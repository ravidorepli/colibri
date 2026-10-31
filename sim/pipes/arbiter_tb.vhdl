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
  use osvvm.coveragepkg.all;

library colibri;
  context colibri.common;

entity arbiter_tb is
  generic (

    RUNNER_CFG : string
  );
end entity arbiter_tb;

architecture sim of arbiter_tb is

  -- OSSVM vars
  shared variable v_rv                   : RandomPType;
  shared variable v_bin1, v_bin2, v_bin3 : CovPType;

  constant c_CLK_PERIOD : time      := 10 ns;
  signal   reset        : std_logic := '1'; --! reset
  signal   clk          : std_logic := '1'; --! clock

  constant c_NUM_INPUTS : positive                                    := 4;
  constant c_MAX_HOLD   : positive                                    := 5;
  signal   requests     : std_logic_vector(c_NUM_INPUTS - 1 downto 0) := (others => 'X'); --! req input
  signal   grants       : std_logic_vector(c_NUM_INPUTS - 1 downto 0);                    --! datao output

  function count_ones (vec : std_logic_vector) return integer is

    variable v_ret : integer := 0;

  begin

    v_ret := 0;

    for i in vec'range loop

      if (vec(i) = '1') then
        v_ret := v_ret + 1;
      end if;

    end loop;

    return v_ret;

  end function;

begin

  clk <= not clk after c_CLK_PERIOD / 2;

  dut : entity colibri.arbiter(rtl)
    generic
    map (
      g_NUM_INPUTS => c_NUM_INPUTS
    )
    port map (
      clk_i      => clk,
      reset_i    => reset,
      requests_i => requests,
      grants_o   => grants
    );

  proc_seq : process is
  begin

    ---------------- VUNIT SETUP ---------------
    test_runner_setup(runner, RUNNER_CFG);
    info("Starting OSVVM");

    --- OSVVM SETUP ---
    -- Set up coverage bins
    v_bin1.AddBins("no incoming request", 2, ONE_BIN);
    v_bin2.AddBins("more than one request", 2, ONE_BIN);
    v_bin3.AddBins("single request ", 2, ONE_BIN);

    if run("arbiter_coverage") then
      info("Starting the test");
      wait for c_CLK_PERIOD;
      reset <= '0';

      loop
        wait for c_CLK_PERIOD;
        -- Collect coverage data
        v_bin1.ICover(to_integer(or requests = '0'));
        v_bin2.ICover(to_integer(count_ones(requests) > 1));
        v_bin3.ICover(to_integer(count_ones(requests) = 1));
        -- Stop the test when all coverage goals have been met
        exit when
        v_bin1.IsCovered and
        v_bin2.IsCovered and
        v_bin3.IsCovered;
      end loop;

      info("Coverage goals met!");
    end if;

    -- Print coverage data
    v_bin1.WriteBin;
    v_bin2.WriteBin;
    v_bin3.WriteBin;
    -- VUnit cleanup
    test_runner_cleanup(runner);

  end process proc_seq;

  -- Generate random requests
  proc_req : process is
  begin

    for i in 0 to v_rv.RandInt(0, c_MAX_HOLD) loop
      requests <= v_rv.RandSlv(c_NUM_INPUTS);
      wait for c_CLK_PERIOD;
    end loop;

  end process proc_req;

  -- Check that the output from the DUT matches the behavioral model
  proc_verify : process is
  begin

    wait for c_CLK_PERIOD;

    if (reset = '0') then
      check(count_ones(grants) <= 1, "grants should only contain a single high bit");
      if (or requests = '1') then
        check(or (requests and grants) = '1', "no grants when a request is present");
      end if;
    end if;

  end process proc_verify;

  test_runner_watchdog(runner, 3000 ns);

end architecture sim;
