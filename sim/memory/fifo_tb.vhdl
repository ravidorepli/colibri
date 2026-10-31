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

entity fifo_tb is
  generic (
    RUNNER_CFG : string
  );
end entity fifo_tb;

architecture sim of fifo_tb is

  -- OSSVM vars
  shared variable v_rv                                                   : RandomPType;
  shared variable v_bin1, v_bin2, v_bin3, v_bin4, v_bin5, v_bin6, v_bin7 : CovPType;

  constant c_CLK_PERIOD : time      := 10 ns;
  signal   reset        : std_logic := '1'; --! reset
  signal   clk          : std_logic := '1'; --! clock

  constant c_NUM_WORDS           : positive                                    := 8;
  constant c_DATA_WIDTH          : positive                                    := 8;
  signal   data                  : std_logic_vector(c_DATA_WIDTH - 1 downto 0) := (others => 'X'); --! data input
  signal   wrreq                 : std_logic                                   := 'X';             --! write request
  signal   rdreq                 : std_logic                                   := 'X';             --! read request
  signal   q                     : std_logic_vector(c_DATA_WIDTH - 1 downto 0);                    --! datao output
  signal   usedw                 : unsigned(log2ceil(c_NUM_WORDS) downto 0);                       --! used words
  signal   empty                 : std_logic;                                                      --! empty signal
  signal   full                  : std_logic;                                                      --! full signal
  -- Testbench FIFO signals
  signal          fifo_out       : integer;
  signal          fifo_out_valid : std_logic := '0';
  shared variable v_fifo_cosim   : linked_list;

begin

  clk <= not clk after c_CLK_PERIOD / 2;

  dut : entity colibri.fifo(rtl)
    generic
    map (
      g_NUM_WORDS   => c_NUM_WORDS,
      g_INPUT_WIDTH => c_DATA_WIDTH,
      g_OUTPUT_WIDTH => c_DATA_WIDTH
    )
    port map (
      clk_i   => clk,
      reset_i => reset,
      data_i  => data,
      wrreq_i => wrreq,
      rdreq_i => rdreq,
      q_o     => q,
      usedw_o => usedw,
      empty_o => empty,
      full_o  => full
    );

  proc_sequencer : process is
  begin

    ---------------- VUNIT SETUP ---------------
    test_runner_setup(runner, RUNNER_CFG);
    info("Starting OSVVM");

    --- OSVVM SETUP ---
    -- Set up coverage v_bins
    v_bin1.AddBins("Write while empty", 2, ONE_BIN);
    v_bin2.AddBins("Read while full", 2, ONE_BIN);
    v_bin3.AddBins("Read and write ", ONE_BIN);
    v_bin4.AddBins("Read without write", ONE_BIN);
    v_bin5.AddBins("Write without read", ONE_BIN);
    v_bin6.AddBins("Write while full", ONE_BIN);
    v_bin7.AddBins("Read while empty", ONE_BIN);

    if run("fifo_coverage") then
      info("Starting the test");
      wait for c_CLK_PERIOD;
      reset <= '0';

      loop
        wait for c_CLK_PERIOD;

        -- Collect coverage data
        v_bin1.ICover(to_integer(wrreq = '1' and empty = '1'));
        v_bin2.ICover(to_integer(rdreq = '1' and full = '1'));
        v_bin3.ICover(to_integer(rdreq = '1' and wrreq = '1' and empty = '0' and full = '0'));
        v_bin4.ICover(to_integer(rdreq = '1' and wrreq = '0' and empty = '0'));
        v_bin5.ICover(to_integer(rdreq = '0' and wrreq = '1' and full = '0'));
        v_bin6.ICover(to_integer(wrreq = '1' and full = '1'));
        v_bin7.ICover(to_integer(rdreq = '1' and empty = '1'));
        -- Stop the test when all coverage goals have been met
        exit when
        v_bin1.IsCovered and
        v_bin2.IsCovered and
        v_bin3.IsCovered and
        v_bin4.IsCovered and
        v_bin5.IsCovered and
        v_bin6.IsCovered and
        v_bin7.IsCovered;
      end loop;

      info("Coverage goals met!");
      -- Make sure that the DUT is empty before terminating the test
      wrreq <= force '0';
      rdreq <= force '1';

      loop
        wait for c_CLK_PERIOD;
        exit when empty = '1';
      end loop;

    end if;

    -- Print coverage data
    v_bin1.WriteBin;
    v_bin2.WriteBin;
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
  begin

    wrreq <= v_rv.RandSlv(1)(1) and not reset;

    for i in 0 to v_rv.RandInt(0, c_NUM_WORDS) loop
      data <= v_rv.RandSlv(c_DATA_WIDTH);
      wait for c_CLK_PERIOD;
    end loop;

  end process proc_write;

  -- Perform random reads
  proc_read : process is
  begin

    rdreq <= v_rv.RandSlv(1)(1) and not reset;

    for i in 0 to v_rv.RandInt(0, c_NUM_WORDS) loop
      wait for c_CLK_PERIOD;
    end loop;

  end process proc_read;

  -- Check that the output from the DUT matches the behavioral model
  proc_verify : process is
  begin

    wait for c_CLK_PERIOD;

    if (reset = '0') then
      -- Check that DUT and TB FIFO are reporting empty simultaneously
      if (not wrreq) then
        check((empty = '1' and v_fifo_cosim.is_empty) or (empty = '0' and not v_fifo_cosim.is_empty), "empty mismatch");
      end if;

      if (rdreq = '1' and empty = '0') then
        wait for c_CLK_PERIOD;
        check(fifo_out = to_integer(unsigned(q)), "data mismatch");
      end if;
    end if;

  end process proc_verify;

  -- Emulate the DUT
  proc_behavioral_model : process is
  begin

    wait for c_CLK_PERIOD;

    if (reset = '0') then
      -- Emulate a write
      if (wrreq = '1' and full = '0') then
        v_fifo_cosim.push(to_integer(unsigned(data)));
        info("push " & to_hstring(data));
      end if;

      -- Emulate a read
      if (rdreq = '1' and empty = '0') then
        fifo_out       <= v_fifo_cosim.pop;
        fifo_out_valid <= '1';
      else
        fifo_out_valid <= '0';
      end if;
    end if;

  end process proc_behavioral_model;

  test_runner_watchdog(runner, 10 ms);

end architecture sim;
