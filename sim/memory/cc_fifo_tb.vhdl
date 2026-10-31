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
use work.data_structures.all;

entity cc_fifo_tb is
  generic (
    RUNNER_CFG    : string;
    g_ENABLE_FWFT : boolean := false
  );
end entity cc_fifo_tb;

architecture sim of cc_fifo_tb is

  constant c_NUM_WORDS  : positive := 8;
  constant c_DATA_WIDTH : positive := 8;

  -- OSSVM vars
  shared variable v_rv                                                   : randomptype;
  shared variable v_bin1, v_bin2, v_bin3, v_bin4, v_bin5, v_bin6, v_bin7 : covptype;
  -- vunit queue
  shared variable v_queue                                                : queue_t;
  shared variable v_lastq                                                : queue_t;

  constant c_CLK_PERIOD_WR : time      := 10 ns;
  constant c_CLK_PERIOD_RD : time      := 11 ns;
  signal   reset           : std_logic := '1'; --! reset
  signal   wrclk           : std_logic := '1'; --! write clock
  signal   rdclk           : std_logic := '1'; --! read clock

  signal data      : std_logic_vector(c_DATA_WIDTH - 1 downto 0) := (others => 'X');
  signal wrq       : std_logic_vector(c_DATA_WIDTH - 1 downto 0) := (others => 'X');
  signal wrq_valid : std_logic                                   := 'X';
  signal wrreq     : std_logic                                   := 'X';
  signal rdreq     : std_logic                                   := 'X';
  signal q         : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal wrusedw   : unsigned(log2ceil(c_NUM_WORDS) - 1 downto 0);
  signal rdusedw   : unsigned(log2ceil(c_NUM_WORDS) - 1 downto 0);
  signal wrempty   : std_logic;
  signal wrfull    : std_logic;
  signal rdempty   : std_logic;
  signal rdfull    : std_logic;

begin

  osvvm.TbUtilPkg.CreateClock(rdclk, c_CLK_PERIOD_RD);
  osvvm.TbUtilPkg.CreateClock(wrclk, c_CLK_PERIOD_WR);
  osvvm.TbUtilPkg.CreateReset(reset, '1', rdclk, c_CLK_PERIOD_WR, c_CLK_PERIOD_RD);

  dut : entity colibri.cc_fifo(rtl)
    generic map (

      g_NUM_WORDS    => c_NUM_WORDS,
      g_INPUT_WIDTH  => c_DATA_WIDTH,
      g_OUTPUT_WIDTH => c_DATA_WIDTH,
      g_PEEK_NEXT    => true,
      g_ENABLE_FWFT  => g_ENABLE_FWFT
    )
    port map (
      wrclk_i     => wrclk,
      rdclk_i     => rdclk,
      reset_i     => reset,
      data_i      => data,
      wrreq_i     => wrreq,
      rdreq_i     => rdreq,
      q_o         => q,
      wrusedw_o   => wrusedw,
      rdusedw_o   => rdusedw,
      wrempty_o   => wrempty,
      wrfull_o    => wrfull,
      rdempty_o   => rdempty,
      rdfull_o    => rdfull,
      wrq_o       => wrq,
      wrq_valid_o => wrq_valid
    );

  proc_sequencer : process is
  begin

    ---------------- VUNIT SETUP ---------------
    test_runner_setup(runner, RUNNER_CFG);
    info("Creating Test Queue");
    v_queue := new_queue;
    v_lastq := new_queue;
    info("Starting OSVVM");

    --- OSVVM SETUP ---
    -- Set up coverage v_bins
    v_bin3.AddBins("Read and write ", ONE_BIN);
    v_bin4.AddBins("only read", ONE_BIN);
    v_bin5.AddBins("only write", ONE_BIN);
    v_bin6.AddBins("Write while full", ONE_BIN);
    v_bin7.AddBins("Read while empty", ONE_BIN);
    info("Waiting for reset release...");
    osvvm.TbUtilPkg.WaitForLevel(reset, '0');

    info("Starting the test");
    osvvm.TbUtilPkg.WaitForClock(wrclk, 1);

    loop
      osvvm.TbUtilPkg.WaitForClock(wrclk, 1);

      -- Collect coverage data
      v_bin3.ICover(to_integer(rdreq = '1' and wrreq = '1' and rdempty = '0' and wrfull = '0'));
      v_bin4.ICover(to_integer(rdreq = '1' and wrreq = '0' and rdempty = '0'));
      v_bin5.ICover(to_integer(rdreq = '0' and wrreq = '1' and wrfull = '0'));
      v_bin6.ICover(to_integer(wrreq = '1' and wrfull = '1'));
      v_bin7.ICover(to_integer(rdreq = '1' and rdempty = '1'));
      -- Stop the test when all coverage goals have been met
      exit when
        v_bin3.IsCovered and
        v_bin4.IsCovered and
        v_bin5.IsCovered and
        v_bin6.IsCovered and
        v_bin7.IsCovered;

    end loop;

    info("Coverage goals met!");

    loop

      osvvm.TbUtilPkg.WaitForClock(rdclk, 1);
      exit when rdempty = '1';
    end loop;

    -- Print coverage data
    v_bin3.WriteBin;
    v_bin4.WriteBin;
    v_bin5.WriteBin;
    v_bin6.WriteBin;
    v_bin7.WriteBin;
    -- VUnit cleanup
    test_runner_cleanup(runner);

  end process proc_sequencer;

  -- Generate random input
  proc_write : process is

    variable v_data : std_logic_vector(c_DATA_WIDTH - 1 downto 0);

  begin

    osvvm.TbUtilPkg.WaitForLevel(reset, '0');
    osvvm.TbUtilPkg.WaitForClock(wrclk, 3);

    loop
      wrreq <= '0';

      if (v_rv.RandSlv(1)(1) and not reset) then
        wrreq <= '1';
        data  <= v_rv.RandSlv(c_DATA_WIDTH);
        wait for 1 ns;

        if (not wrfull) then
          v_data := data;
          info("push " & to_hstring(v_data));
          push_std_ulogic_vector(v_queue, std_ulogic_vector(v_data));
          push_std_ulogic_vector(v_lastq, std_ulogic_vector(v_data));
        else
          info("FULL: dropping " & to_hstring(data));
        end if;

        osvvm.TbUtilPkg.WaitForClock(wrclk, 1);
        wrreq <= '0';
      end if;

      osvvm.TbUtilPkg.WaitForClock(wrclk, v_rv.randint(1,  10));
    end loop;

  end process proc_write;

  -- Perform random reads
  proc_read : process is

    variable v_q : q'subtype;

  begin

    rdreq <= '0';
    osvvm.TbUtilPkg.WaitForLevel(reset, '0');
    osvvm.TbUtilPkg.WaitForClock(rdclk, 1);

    loop
      rdreq <= '0';

      if (v_rv.RandSlv(1)(1) and not reset) then
        rdreq <= '1';
        if (not g_ENABLE_FWFT) then
          osvvm.TbUtilPkg.WaitForClock(rdclk, 1);
          rdreq <= '0';
        end if;
        if (not rdempty) then
          wait for 1 ns;

          v_q := std_logic_vector(pop_std_ulogic_vector(v_queue));
          info("pop "&to_hstring(v_q));

          check(v_q = q, "data mismatch! Got "&to_hstring(q)&" Exp "&to_hstring(v_q));
        else
          info("EMPTY");
        end if;
        if (g_ENABLE_FWFT) then
          osvvm.TbUtilPkg.WaitForClock(rdclk, 1);
          rdreq <= '0';
        end if;
      end if;

      osvvm.TbUtilPkg.WaitForClock(rdclk, v_rv.randint(1, 10));

    end loop;

  end process proc_read;

  test_runner_watchdog(runner, 500 us);

  proc_peek : process is

    variable v_q : q'subtype;

  begin

    osvvm.TbUtilPkg.WaitForLevel(reset, '0');
    osvvm.TbUtilPkg.WaitForClock(wrclk, 1);

    loop
      osvvm.TbUtilPkg.WaitForClock(wrclk, 1);
      wait for 0 ns;
      if (wrq_valid) then
        wait for 1 ns;
        v_q := std_logic_vector(pop_std_ulogic_vector(v_lastq));
        check(v_q = wrq, "peek mismatch! Got "&to_hstring(wrq)&" Exp "&to_hstring(v_q));
      end if;

    end loop;

  end process proc_peek;

end architecture sim;
