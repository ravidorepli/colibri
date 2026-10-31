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

----------------------------------------------------------------------------------------------------

entity ram_tb is
  generic (
    RUNNER_CFG     : string;
    g_REGISTER_IN  : boolean := false;
    g_REGISTER_OUT : boolean := true;
    g_WRITE_FIRST  : boolean := true
  );
end entity ram_tb;

----------------------------------------------------------------------------------------------------

architecture sim of ram_tb is

  -- Clock period
  constant        c_CLK_PERIOD   : time    := 5 ns;
  constant        c_N_WORDS      : natural := 32;
  constant        c_DATA_WIDTH   : natural := 8;
  shared variable v_rv           : randomptype;
  shared variable v_bin1, v_bin2 : covptype;
  signal          acov           : coverageidtype;

  signal clk   : std_logic := '1';
  signal reset : std_logic := '1';

  signal we      : std_logic := '0';
  signal addr    : unsigned(log2ceil(c_N_WORDS) - 1 downto 0);
  signal data, q : std_logic_vector(c_DATA_WIDTH - 1 downto 0);

begin ----------------------------------------------------------------------------------------------

  osvvm.TbUtilPkg.CreateClock(clk, c_CLK_PERIOD);

  ------------------------------------------------------------------------------
  --! Unit under test
  ------------------------------------------------------------------------------
  dut : entity colibri.ram
    generic map (
      g_N_WORDS      => c_N_WORDS,
      g_DATA_WIDTH   => c_DATA_WIDTH,
      g_REGISTER_IN  => g_REGISTER_IN,
      g_REGISTER_OUT => g_REGISTER_OUT,
      g_WRITE_FIRST  => g_WRITE_FIRST
    )
    port map (
      clk_i   => clk,
      reset_i => reset,
      addr_i  => addr,
      we_i    => we,
      data_i  => data,
      q_o     => q
    );

  ------------------------------------------------------------------------------
  --! Coverage verification (main VUnit process)
  ------------------------------------------------------------------------------
  proc_seq : process is
  begin

    test_runner_setup(runner, RUNNER_CFG);
    info("Starting OSVVM");
    --- OSVVM SETUP ---
    --
    acov <= NewID("ACov");
    wait for 0 ns;
    AddBins(acov, 5, GenBin(0, c_N_WORDS - 1));
    -- Set up coverage v_bins
    v_bin1.AddBins("write", c_N_WORDS, ONE_BIN);
    v_bin2.AddBins("read", c_N_WORDS, ONE_BIN);

    osvvm.TbUtilPkg.WaitForClock(clk, 3);
    reset <= '0';
    osvvm.TbUtilPkg.WaitForClock(clk, 1);

    if run("ram_coverage") then

      loop
        osvvm.TbUtilPkg.WaitForClock(clk, 1);

        -- Collect coverage data
        v_bin1.ICover(to_integer(we = '1'));
        v_bin2.ICover(to_integer(we = '0'));
        ICover(acov, to_integer(addr));
        -- Stop the test when all coverage goals have been met
        exit when
          v_bin1.IsCovered and
          v_bin2.IsCovered and
          IsCovered(acov);
      end loop;

      info("Coverage goals met!");
    end if;

    osvvm.TbUtilPkg.WaitForClock(clk, 10);
    -- Print coverage data
    v_bin1.WriteBin;
    v_bin2.WriteBin;

    test_runner_cleanup(runner);

  end process proc_seq;

  ------------------------------------------------------------------------------
  --! RAM interface verification
  ------------------------------------------------------------------------------
  proc_ram_model : process is

    variable v_addr : addr'subtype;
    variable v_data : data'subtype;

  begin

    wait until not reset;

    loop

      if (v_rv.RandSlv(1)(1)) then
        v_addr := to_unsigned(GetRandPoint(acov), addr'length);
        v_data := v_rv.RandSlv(c_DATA_WIDTH);
        addr   <= v_addr;
        data   <= v_data;

        we <= '1';
        osvvm.TbUtilPkg.WaitForClock(clk, 1);
        we <= '0';
        info("write " & to_hstring(addr) & " -> " & to_hstring(data));

        if (g_REGISTER_IN) then
          osvvm.TbUtilPkg.WaitForClock(clk, 1);
        end if;

        if (not g_WRITE_FIRST) then
          osvvm.TbUtilPkg.WaitForClock(clk, 1);
        end if;

        addr <= v_addr;
        if (g_REGISTER_OUT) then
          osvvm.TbUtilPkg.WaitForClock(clk, 1);
        end if;

        wait for c_CLK_PERIOD / 10;
        check(q = v_data, "read " & to_hstring(v_addr) &
              " -> " & to_hstring(v_data) & " found " & to_hstring(q));

        if (not g_REGISTER_OUT) then
          osvvm.TbUtilPkg.WaitForClock(clk, 1);
        end if;
      else
        osvvm.TbUtilPkg.WaitForClock(clk, 1);
      end if;

    end loop;

  end process proc_ram_model;

end architecture sim;

----------------------------------------------------------------------------------------------------