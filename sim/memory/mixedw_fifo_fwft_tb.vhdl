-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  use osvvm.randompkg.all;
  use osvvm.coveragepkg.all;

library colibri;
  use colibri.utils.all;

library vunit_lib;
  context vunit_lib.vunit_context;

use work.data_structures.all;

entity mixedw_fifo_fwft_tb is
  generic (
    RUNNER_CFG : string
  );
end entity mixedw_fifo_fwft_tb;

architecture sim of mixedw_fifo_fwft_tb is

  -- OSSVM vars
  shared variable v_rv                                                   : RandomPType;
  shared variable v_bin1, v_bin2, v_bin3, v_bin4, v_bin5, v_bin6, v_bin7 : CovPType;

  -- Clock period
  constant c_CLK_PERIOD  : time := 5 ns;
  -- Generics
  constant c_NUM_WORDS   : positive := 40;
  constant c_WNUM_WORDS  : positive := 4;
  constant c_WDATA_WIDTH : positive := 12;
  constant c_RDATA_WIDTH : positive := 8;
  -- Constants
  constant c_BUF_UNIT    : integer := greatest_common_div(c_WDATA_WIDTH, c_RDATA_WIDTH);
  constant c_WR_UNITS    : integer := c_WDATA_WIDTH / c_BUF_UNIT;
  constant c_RD_UNITS    : integer := c_RDATA_WIDTH / c_BUF_UNIT;
  -- Ports
  signal clk             : std_logic := '1';
  signal reset           : std_logic := '1';
  signal data            : std_logic_vector(c_WDATA_WIDTH - 1 downto 0);
  signal wrreq           : std_logic;
  signal empty           : std_logic;
  signal full            : std_logic;
  signal q               : std_logic_vector(c_RDATA_WIDTH - 1 downto 0);
  signal rdreq           : std_logic;

  -- Testbench FIFO signals
  signal          fifo_out       : std_logic_vector(c_RDATA_WIDTH - 1 downto 0);
  signal          fifo_out_valid : std_logic := '0';
  shared variable v_fifo_cosim   : linked_list;
  signal          q_delay        : std_logic_vector(c_RDATA_WIDTH - 1 downto 0); --! datao output delayed
  signal          cosim_empty    : std_logic;

begin

  clk <= not clk after c_CLK_PERIOD / 2;

  fifo_inst : entity colibri.fifo
    generic map (
      g_NUM_WORDS   => c_WNUM_WORDS,
      g_INPUT_WIDTH => c_WDATA_WIDTH,
      g_OUTPUT_WIDTH => c_RDATA_WIDTH,
      g_ENABLE_FWFT => true
    )
    port map (
      clk_i   => clk,
      reset_i => reset,
      data_i  => data,
      wrreq_i => wrreq,
      rdreq_i => rdreq,
      q_o     => q,
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
    v_bin4.AddBins("only read", ONE_BIN);
    v_bin5.AddBins("only write", ONE_BIN);
    v_bin6.AddBins("Write while full", ONE_BIN);
    v_bin7.AddBins("Read while empty", ONE_BIN);

    if run("mixedw_fifo_coverage") then
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
      data <= v_rv.RandSlv(c_WDATA_WIDTH);
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
  proc_verify_rd : process is
  begin

    wait for c_CLK_PERIOD;

    if (reset = '0') then
      if (rdreq = '1' and empty = '0') then
        wait for c_CLK_PERIOD;
        check(fifo_out = q_delay, "data mismatch: " & to_hstring(fifo_out) & " /= " & to_hstring(q));
      end if;
    end if;

  end process proc_verify_rd;

  -- Emulate the DUT
  proc_behavioral_model_wr : process is

    variable v_data : std_logic_vector(c_BUF_UNIT - 1 downto 0);

  begin

    wait for c_CLK_PERIOD;

    if (reset = '0') then
      -- Emulate a write
      if (wrreq = '1' and full = '0') then

        for i in 0 to c_WR_UNITS - 1 loop
          v_data := data(data'left - (c_BUF_UNIT * i) downto data'length - (c_BUF_UNIT * (i + 1)));
          v_fifo_cosim.push(to_integer(unsigned(v_data)));
        end loop;

        info("push " & to_hstring(data));
      end if;
    end if;

  end process proc_behavioral_model_wr;

  proc_read_cosim : process is

    variable v_tmp : integer;
    variable v_q   : std_logic_vector(c_RDATA_WIDTH - 1 downto 0);

  begin

    wait for c_CLK_PERIOD;

    if (reset = '0') then
      -- Emulate a read
      if (rdreq = '1' and empty = '0') then

        for i in 0 to c_RD_UNITS - 1 loop
          v_tmp := v_fifo_cosim.pop;
          v_q(v_q'left - (c_BUF_UNIT * i) downto v_q'length - (c_BUF_UNIT * (i + 1)))
                := std_logic_vector(to_unsigned(v_tmp, c_BUF_UNIT));
        end loop;

        info("pull " & to_hstring(v_q));
        fifo_out       <= v_q;
        fifo_out_valid <= '1';
      else
        fifo_out_valid <= '0';
      end if;
    end if;

  end process proc_read_cosim;

  q_delay <= q when rising_edge(clk);
  test_runner_watchdog(runner, 10 ms);

end architecture sim;
