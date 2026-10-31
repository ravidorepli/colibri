-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

--! @file ring_buffer_tb.vhdl
--! @brief Automated Testbench for Ring Buffer
--! @author Alberto Perro
--! @date 25-02-2026 Updated
--! @version 1.0
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.osvvmcontext;
  use osvvm.scoreboardpkg_slv.all;

library colibri;

library vunit_lib;
  context vunit_lib.vunit_context;

--==================================================================================================
--! @brief Automated testbench for the ring_buffer entity
--! @details
--! This testbench verifies the correct behavior of a circular buffer that supports
--! overwriting oldest data when full. It utilizes:
--! - **OSVVM Scoreboarding**: To ensure data integrity and correct ordering.
--! - **Functional Coverage**: To verify corner cases like reading when empty,
--!    overwriting when full, and simultaneous read/write at full capacity.
--! - **Randomized Stimulus**: Using RandomPType to vary transaction density and delays.
--==================================================================================================

entity ring_buffer_tb is
  generic (
    RUNNER_CFG : string
  );
end entity ring_buffer_tb;

architecture bench of ring_buffer_tb is

  -- Simulation Constants
  constant c_CLK_PERIOD : time     := 5 ns;
  constant c_NUM_WORDS  : positive := 4;
  constant c_DATA_WIDTH : positive := 8;

  -- Signals
  signal clk       : std_logic                                   := '1';
  signal reset     : std_logic                                   := '1';
  signal snk_data  : std_logic_vector(c_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal snk_valid : std_logic                                   := '0';
  signal src_data  : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal src_valid : std_logic;
  signal src_ready : std_logic                                   := '0';
  signal datascoreboard : scoreboardidtype := NewID("data_sb");

  -- OSVVM Shared Variables
  shared variable testcov        : covptype;
  shared variable rv             : randomptype;

  -- Track depth for Overwrite-style buffer logic
  signal buffer_count : integer := 0;

begin

  -- Clock and Reset Generation
  osvvm.TbUtilPkg.CreateClock(clk, c_CLK_PERIOD);
  osvvm.TbUtilPkg.CreateReset(reset, '1', clk, c_CLK_PERIOD, 5 * c_CLK_PERIOD);

  -- Device Under Test
  ring_buffer_inst : entity colibri.ring_buffer
    generic map (
      g_NUM_WORDS  => c_NUM_WORDS,
      g_DATA_WIDTH => c_DATA_WIDTH
    )
    port map (
      clk_i       => clk,
      reset_i     => reset,
      snk_data_i  => snk_data,
      snk_valid_i => snk_valid,
      src_data_o  => src_data,
      src_valid_o => src_valid,
      src_ready_i => src_ready
    );

  -- Internal Monitor
  proc_monitor : process (clk) is
  begin

    if rising_edge(clk) then
      if (reset = '1') then
        buffer_count <= 0;
      else
        if (snk_valid = '1' and (src_ready = '1' and src_valid = '1')) then
          -- Simultaneous Read/Write: Count never changes
          buffer_count <= buffer_count;
        elsif (snk_valid = '1' and buffer_count < c_NUM_WORDS) then
          -- Write only, count up
          buffer_count <= buffer_count + 1;
        elsif (src_ready = '1' and src_valid = '1' and buffer_count > 0) then
          -- Read only, count down
          buffer_count <= buffer_count - 1;
        end if;
      end if;
    end if;

  end process proc_monitor;

  -- Main Control Process
  proc_main : process is

    variable errorcount : integer := 0;

  begin

    test_runner_setup(runner, RUNNER_CFG);
    rv.InitSeed(rv'instance_name);

    -- Operation Bins
    testcov.AddBins("Normal Write",   5, GenBin(0));
    testcov.AddBins("Overwrite Write", 5, GenBin(1));
    testcov.AddBins("Normal Read",    5, GenBin(2));
    testcov.AddBins("Empty Read",     5, GenBin(3));
    testcov.AddBins("Full Read Write", 5, GenBin(4));
    info("Waiting for reset release...");
    osvvm.TbUtilPkg.WaitForLevel(reset, '0');

    loop
      osvvm.TbUtilPkg.WaitForClock(clk, 1);
      exit when testcov.IsCovered;
    end loop;

    info("All Coverage Targets Met (including Full Read-Write). Draining...");

    while buffer_count > 0 loop
      osvvm.TbUtilPkg.WaitForClock(clk, 1);
    end loop;

    osvvm.TbUtilPkg.WaitForClock(clk, 10);
    testcov.WriteBin;
    errorcount := GetErrorCount(datascoreboard);
    test_runner_cleanup(runner);

  end process proc_main;

  -- RANDOMIZED WRITER
  proc_writer : process is

    variable data_val   : integer := 1;
    variable dummy_slv  : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
    variable is_reading : boolean;

  begin

    snk_valid <= '0';
    osvvm.TbUtilPkg.WaitForLevel(reset, '0');

    loop

      if (rv.DistInt((80, 20)) = 0) then -- Slightly higher pressure to hit Full states
        snk_valid <= '1';
        snk_data  <= std_logic_vector(to_unsigned(data_val, c_DATA_WIDTH));

        wait for 0 ns;
        is_reading := (src_ready = '1' and src_valid = '1');

        if (buffer_count >= c_NUM_WORDS) then
          if (is_reading) then
            info("WRITER: Full Read-Write. Space vacated while writing. No data lost.");
            testcov.ICover(4); -- Bin: Full Read Write
            osvvm.scoreboardpkg_slv.Push(datascoreboard, snk_data);
          else
            info("WRITER: Buffer FULL. Overwriting oldest with: " & to_hstring(snk_data));
            testcov.ICover(1); -- Bin: Overwrite Write
            if (not osvvm.scoreboardpkg_slv.Empty(datascoreboard)) then
              dummy_slv := osvvm.scoreboardpkg_slv.Pop(datascoreboard);
            end if;
            osvvm.scoreboardpkg_slv.Push(datascoreboard, snk_data);
          end if;
        else
          info("WRITER: Normal Write: " & to_hstring(snk_data));
          testcov.ICover(0);   -- Bin: Normal Write
          osvvm.scoreboardpkg_slv.Push(datascoreboard, snk_data);
        end if;
        data_val := data_val + 1;
      else
        snk_valid <= '0';
      end if;

      osvvm.TbUtilPkg.WaitForClock(clk, 1);
      snk_valid <= '0';
      osvvm.TbUtilPkg.WaitForClock(clk, rv.RandInt(0, 1));
      exit when testcov.IsCovered;
    end loop;

    wait;

  end process proc_writer;

  -- RANDOMIZED READER
  proc_reader : process is
  begin

    src_ready <= '0';
    osvvm.TbUtilPkg.WaitForLevel(reset, '0');

    loop

      if (rv.DistInt((60, 40)) = 0) then
        src_ready <= '1';
        wait for 1 ns;

        if (src_valid = '1') then
          if osvvm.scoreboardpkg_slv.Empty(datascoreboard) then
            error("DUT provided " & to_hstring(src_data) & " but Scoreboard is empty!");
          else
            info("READER: Data Read: " & to_hstring(src_data));
            testcov.ICover(2); -- Bin: Normal Read
            osvvm.scoreboardpkg_slv.Check(datascoreboard, src_data);
          end if;
        else
          info("READER: Read attempt while empty.");
          testcov.ICover(3);   -- Bin: Empty Read
        end if;
      else
        src_ready <= '0';
      end if;

      osvvm.TbUtilPkg.WaitForClock(clk, 1);
      src_ready <= '0';
      osvvm.TbUtilPkg.WaitForClock(clk, rv.RandInt(0, 1));
      exit when testcov.IsCovered and osvvm.scoreboardpkg_slv.Empty(datascoreboard);
    end loop;

    wait;

  end process proc_reader;

  test_runner_watchdog(runner, 10 ms);

end architecture bench;
