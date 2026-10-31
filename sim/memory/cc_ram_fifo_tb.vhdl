--! @file cc_ram_fifo_tb.vhdl
--! @brief Testbench for the dual clock ram-based FIFO
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 05-03-2026 Created
--! @version 0.1
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library vunit_lib;
  context vunit_lib.vunit_context;

library osvvm;
  use osvvm.randompkg.all;
  use osvvm.coveragepkg.all;
  context osvvm.osvvmcontext;

library colibri;
  context colibri.common;

-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

entity cc_ram_fifo_tb is
  generic (

    RUNNER_CFG     : string;
    g_INPUT_WIDTH  : positive := 16;
    g_OUTPUT_WIDTH : positive := 8
  );
end entity cc_ram_fifo_tb;

architecture sim of cc_ram_fifo_tb is

  constant c_NUM_WORDS : positive := 8;
  --! internal memory width
  constant c_MEM_WIDTH : positive := minimum(g_INPUT_WIDTH, g_OUTPUT_WIDTH);
  constant c_MEM_DEPTH : positive := maximum(g_INPUT_WIDTH, g_OUTPUT_WIDTH) / c_MEM_WIDTH * c_NUM_WORDS;
  constant c_WR_RATIO  : positive := g_INPUT_WIDTH / c_MEM_WIDTH;
  constant c_RD_RATIO  : positive := g_OUTPUT_WIDTH / c_MEM_WIDTH;
  constant c_WR_WORDS  : positive := c_MEM_DEPTH / c_WR_RATIO;
  constant c_RD_WORDS  : positive := c_MEM_DEPTH / c_RD_RATIO;

  -- OSSVM vars
  shared variable v_rv                                                   : randomptype;
  shared variable v_bin1, v_bin2, v_bin3, v_bin4, v_bin5, v_bin6, v_bin7 : covptype;
  -- vunit queue
  shared variable v_queue                                                : queue_t;

  constant c_CLK_PERIOD_WR : time      := 10 ns;
  constant c_CLK_PERIOD_RD : time      := 11 ns;
  signal   reset           : std_logic := '1'; --! reset
  signal   wrclk           : std_logic := '1'; --! write clock
  signal   rdclk           : std_logic := '1'; --! read clock

  signal data    : std_logic_vector(g_INPUT_WIDTH - 1 downto 0) := (others => 'X');
  signal wrreq   : std_logic                                    := 'X';
  signal rdreq   : std_logic                                    := 'X';
  signal q       : std_logic_vector(g_OUTPUT_WIDTH - 1 downto 0);
  signal wrusedw : unsigned(log2ceil(c_WR_WORDS) - 1 downto 0);
  signal rdusedw : unsigned(log2ceil(c_RD_WORDS) - 1 downto 0);
  signal wrempty : std_logic;
  signal wrfull  : std_logic;
  signal rdempty : std_logic;
  signal rdfull  : std_logic;

begin

  osvvm.TbUtilPkg.CreateClock(rdclk, c_CLK_PERIOD_RD);
  osvvm.TbUtilPkg.CreateClock(wrclk, c_CLK_PERIOD_WR);
  osvvm.TbUtilPkg.CreateReset(reset, '1', rdclk, c_CLK_PERIOD_WR, c_CLK_PERIOD_RD);

  dut : entity colibri.cc_ram_fifo(rtl)
    generic map (

      g_NUM_WORDS    => c_NUM_WORDS,
      g_INPUT_WIDTH  => g_INPUT_WIDTH,
      g_OUTPUT_WIDTH => g_OUTPUT_WIDTH
    )
    port map (
      wrclk_i   => wrclk,
      rdclk_i   => rdclk,
      reset_i   => reset,
      data_i    => data,
      wrreq_i   => wrreq,
      rdreq_i   => rdreq,
      q_o       => q,
      wrusedw_o => wrusedw,
      rdusedw_o => rdusedw,
      wrempty_o => wrempty,
      wrfull_o  => wrfull,
      rdempty_o => rdempty,
      rdfull_o  => rdfull
    );

  proc_sequencer : process is
  begin

    ---------------- VUNIT SETUP ---------------
    test_runner_setup(runner, RUNNER_CFG);
    info("Creating Test Queue");
    v_queue := new_queue;
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

    variable v_data : std_logic_vector(c_MEM_WIDTH - 1 downto 0);

  begin

    osvvm.TbUtilPkg.WaitForLevel(reset, '0');
    osvvm.TbUtilPkg.WaitForClock(wrclk, 3);

    loop
      wrreq <= '0';

      if (v_rv.RandSlv(1)(1) and not reset) then
        wrreq <= '1';
        data  <= v_rv.RandSlv(g_INPUT_WIDTH);
        wait for 1 ns;

        for i in 0 to c_WR_RATIO - 1 loop
          if (not wrfull) then
            v_data := data(data'left - i * c_MEM_WIDTH downto data'length - (i + 1) * c_MEM_WIDTH);
            info("push " & to_hstring(v_data));
            push_std_ulogic_vector(v_queue, std_ulogic_vector(v_data));
          else
            info("FULL: dropping " & to_hstring(data));
          end if;
        end loop;

        osvvm.TbUtilPkg.WaitForClock(wrclk, 1);
        wrreq <= '0';
      end if;

      osvvm.TbUtilPkg.WaitForClock(wrclk, v_rv.randint(1, c_WR_RATIO* 10));
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
        osvvm.TbUtilPkg.WaitForClock(rdclk, 1);
        rdreq <= '0';
        if (not rdempty) then
          wait for 1 ns;

          for i in 0 to c_RD_RATIO - 1 loop
            v_q(v_q'left - i * c_MEM_WIDTH downto v_q'length - (i + 1) * c_MEM_WIDTH)
 := std_logic_vector(pop_std_ulogic_vector(v_queue));
            info("pop "&to_hstring(v_q));
          end loop;

          check(v_q = q, "data mismatch! Got "&to_hstring(q)&" Exp "&to_hstring(v_q));
        else
          info("EMPTY");
        end if;
      end if;

      osvvm.TbUtilPkg.WaitForClock(rdclk, v_rv.randint(1, c_RD_RATIO * 10));

    end loop;

  end process proc_read;

  test_runner_watchdog(runner, 500 us);

end architecture sim;
