-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  context colibri.common;

library osvvm;
  context osvvm.osvvmcontext;
  use osvvm.scoreboardpkg_slv.all;

--
library vunit_lib;
  context vunit_lib.vunit_context;

entity bicam_tb is
  generic (
    RUNNER_CFG : string
  );
end entity bicam_tb;

architecture bench of bicam_tb is

  shared variable v_rv                                   : RandomPType;
  shared variable v_bin1, v_bin2, v_bin3, v_bin4, v_bin5 : CovPType;
  signal          sb                                     : ScoreboardIDType := NewID("CAM_SB");
  -- Clock period
  constant CLK_PERIOD                                    : time := 5 ns;
  -- Generics
  constant c_N_WORDS                                     : positive := 8;
  constant c_DATA_WIDTH                                  : positive := 8;
  -- Ports
  signal clk                                             : std_logic := '1';
  signal reset                                           : std_logic := '1';
  signal rdreq                                           : std_logic;
  signal wrreq                                           : std_logic;
  signal clear                                           : std_logic;
  signal data                                            : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal busy                                            : std_logic;
  signal full                                            : std_logic;
  signal match                                           : std_logic;
  signal addr                                            : unsigned(log2ceil(c_N_WORDS) - 1 downto 0);

  type sb_rec_t is record
    match : std_logic;
    addr  : unsigned(log2ceil(c_N_WORDS) - 1 downto 0);
    data  : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  end record sb_rec_t;

  signal sb_rec : sb_rec_t;

  function flat_sb (rec : sb_rec_t) return std_logic_vector is

    variable v_ret : std_logic_vector(log2ceil(c_N_WORDS) + c_DATA_WIDTH downto 0);

  begin

    v_ret := rec.match & std_logic_vector(rec.addr) & rec.data;
    return v_ret;

  end function flat_sb;

  function unflat_sb (vec : std_logic_vector(log2ceil(c_N_WORDS) + c_DATA_WIDTH downto 0)) return sb_rec_t is

    variable v_ret : sb_rec_t;

  begin

    v_ret.match := vec(vec'left);
    v_ret.addr  := unsigned(vec(vec'left -1 downto c_DATA_WIDTH));
    v_ret.data  := vec(c_DATA_WIDTH - 1 downto 0);
    return v_ret;

  end function unflat_sb;

  type sig_t is record
    rdreq : std_logic;
    wrreq : std_logic;
    clear : std_logic;
  end record sig_t;

  signal rec : sig_t;

begin

  -- Generate clock and

  osvvm.TbUtilPkg.CreateClock(clk, CLK_PERIOD);

  bicam_inst : entity colibri.bicam
    generic map (
      g_N_WORDS    => c_N_WORDS,
      g_DATA_WIDTH => c_DATA_WIDTH
    )
    port map (
      clk_i   => clk,
      reset_i => reset,
      rdreq_i => rdreq,
      wrreq_i => wrreq,
      clear_i => clear,
      data_i  => data,
      busy_o  => busy,
      full_o  => full,
      match_o => match,
      addr_o  => addr
    );

  proc_previous : process (clk) is
  begin

    if rising_edge(clk) then
      rec.rdreq <= rdreq;
      rec.wrreq <= wrreq;
      rec.clear <= clear;
    end if;

  end process proc_previous;

  main : process is
  begin

    test_runner_setup(runner, runner_cfg);
    info("Starting OSVVM");
    --- OSVVM SETUP ---
    -- Set up coverage v_bins
    v_bin1.AddBins("write", ONE_BIN);
    v_bin2.AddBins("clear", c_N_WORDS, ONE_BIN);
    v_bin3.AddBins("Search match", ONE_BIN);
    v_bin4.AddBins("Search no match", ONE_BIN);
    v_bin5.AddBins("Write while full", ONE_BIN);

    osvvm.TbUtilPkg.WaitForClock(clk, 3);
    reset <= '0';
    osvvm.TbUtilPkg.WaitForClock(clk, 1);

    if run("coverage") then

      loop
        osvvm.TbUtilPkg.WaitForClock(clk, 1);

        -- Collect coverage data
        v_bin1.ICover(to_integer(wrreq = '1' and clear = '0'));
        v_bin2.ICover(to_integer(rec.wrreq = '1' and rec.clear = '1' and match = '1'));
        v_bin3.ICover(to_integer(rec.rdreq = '1' and rec.wrreq = '0' and match = '1'));
        v_bin4.ICover(to_integer(rec.rdreq = '1' and rec.wrreq = '0' and match = '0'));
        v_bin5.ICover(to_integer(wrreq = '1' and full = '1'));
        -- Stop the test when all coverage goals have been met
        exit when
        v_bin1.IsCovered and
        v_bin2.IsCovered and
        v_bin3.IsCovered and
        v_bin4.IsCovered and
        v_bin5.IsCovered;
      end loop;

      info("Coverage goals met!");
    end if;

    osvvm.TbUtilPkg.WaitForClock(clk, 10);
    -- Print coverage data
    v_bin1.WriteBin;
    v_bin2.WriteBin;
    v_bin3.WriteBin;
    v_bin4.WriteBin;
    v_bin5.WriteBin;

    test_runner_cleanup(runner);

  end process main;

  proc_cam_model : process is

    variable v_vec : std_logic_vector(log2ceil(c_N_WORDS) + c_DATA_WIDTH downto 0);

    variable v_rec : sb_rec_t;

  begin

    wait until rising_edge(clk);

    if (v_rv.RandSlv(1)(1) and not reset and not full) then
      if (v_rv.RandSlv(1)(1)) then
        wrreq       <= '1';
        v_rec.match := '1';
        v_rec.data  := v_rv.RandSlv(c_DATA_WIDTH);
      else
        v_rec.match := '0';
        v_rec.data  := v_rv.RandSlv(c_DATA_WIDTH);
      end if;
      data <= v_rec.data;

      osvvm.TbUtilPkg.WaitForClock(clk, 1);
      wait for 1 ns;

      v_rec.addr := addr;
      info("add " & to_string(v_rec.match) & " " & to_hstring(v_rec.data) & " -> " &  to_hstring((v_rec.addr)));
      -- push to scoreboard
      push(sb, flat_sb(v_rec));
      wrreq      <= '0';
      clear      <= '0';
    elsif (not OSVVM.SCOREBOARDPKG_SLV.Empty(sb)) then
      if (v_rv.RandSlv(1)(1)) then
        if (reset = '0' and wrreq = '0' and busy = '0') then
          rdreq <= '1';
          pop(sb, v_vec);
          v_rec := unflat_sb(v_vec);
          data  <= v_rec.data;
          osvvm.TbUtilPkg.WaitForClock(clk, 1);
          wait for 1 ns;
          rdreq <= '0';
          info("search " & to_string(v_rec.match) & " " & to_hstring(v_rec.data) & " -> " &  to_hstring((v_rec.addr)));
          check(addr = v_rec.addr, "address mismatch");
          check(match = v_rec.match, "match mismatch "&to_string(match)&"=/="&to_string(v_rec.match));
        end if;
      else
        pop(sb, v_vec);
        v_rec := unflat_sb(v_vec);
        info("clear " & to_string(v_rec.match) & " " & to_hstring(v_rec.data) & " -> " &  to_hstring((v_rec.addr)));
        if (v_rec.match) then
          wrreq <= '1';
          clear <= '1';
          data  <= v_rec.data;
          osvvm.TbUtilPkg.WaitForClock(clk, 1);
          wrreq <= '0';
          clear <= '0';
          wait for 1 ns;
          check(addr = v_rec.addr, "clearing mismatch");
        end if;
      end if;
    end if;

    osvvm.TbUtilPkg.WaitForClock(clk, 1);

  end process proc_cam_model;

  test_runner_watchdog(runner, 10 ms);

end architecture bench;
