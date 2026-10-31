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
  use osvvm.scoreboardpkg_slv.all;

library colibri;
  context colibri.common;
  use colibri.mem.all;

entity true_dpram_tb is
  generic (
    RUNNER_CFG     : string;
    g_A_DATA_WIDTH : positive := 8;
    g_B_DATA_WIDTH : positive := 16;
    g_WRITE_FIRST  : boolean  := true;
    g_IMPL_STYLE   : natural  := 0
  );
end entity true_dpram_tb;

architecture sim of true_dpram_tb is

  -- Clock period
  constant c_N_WORDS   : natural  := 8;
  constant c_MAX_W     : positive := maximum(g_A_DATA_WIDTH, g_B_DATA_WIDTH);
  constant c_MEM_WIDTH : positive := minimum(g_A_DATA_WIDTH, g_B_DATA_WIDTH);
  constant c_A_ADDR_W  : natural  := log2ceil(c_N_WORDS * (c_MAX_W / g_A_DATA_WIDTH));
  constant c_B_ADDR_W  : natural  := log2ceil(c_N_WORDS * (c_MAX_W / g_B_DATA_WIDTH));
  constant c_RATIO     : positive := c_MAX_W / minimum(g_A_DATA_WIDTH, g_B_DATA_WIDTH);
  constant c_A_RATIO   : positive := g_A_DATA_WIDTH / c_MEM_WIDTH;
  constant c_B_RATIO   : positive := g_B_DATA_WIDTH / c_MEM_WIDTH;
  constant c_MEM_DEPTH : positive := c_N_WORDS * c_MAX_W / c_MEM_WIDTH;

  constant        c_ACLK_PERIOD                  : time             := 7 ns;
  constant        c_BCLK_PERIOD                  : time             := 5 ns;
  shared variable v_rv                           : randomptype;
  signal          sb                             : scoreboardidtype := NewID("RAM_SB");
  shared variable v_bin1, v_bin2, v_bin3, v_bin4 : covptype;
  signal          acov                           : coverageidtype;
  signal          clka                           : std_logic        := '1';
  signal          clkb                           : std_logic        := '1';
  signal          wra                            : std_logic        := '0';
  signal          wrb                            : std_logic        := '0';
  signal          addra                          : unsigned(c_A_ADDR_W - 1 downto 0);
  signal          addrb                          : unsigned(c_B_ADDR_W - 1 downto 0);
  signal          dataa                          : std_logic_vector(g_A_DATA_WIDTH - 1 downto 0);
  signal          datab                          : std_logic_vector(g_B_DATA_WIDTH - 1 downto 0);
  signal          qa                             : std_logic_vector(g_A_DATA_WIDTH - 1 downto 0);
  signal          qb                             : std_logic_vector(g_B_DATA_WIDTH - 1 downto 0);

  shared variable v_mem : slv_array_t(0 to c_MEM_DEPTH - 1)(c_MEM_WIDTH - 1 downto 0) := (others => (others => '0'));

  subtype sb_vec_t is std_logic_vector(log2ceil(c_MEM_DEPTH) + c_MEM_WIDTH - 1 downto 0);

  -- Scoreboard Record: Stores what was written exactly
  type sb_rec_t is record
    addr : unsigned(log2ceil(c_MEM_DEPTH) - 1 downto 0);
    data : std_logic_vector(c_MEM_WIDTH - 1 downto 0);
  end record sb_rec_t;

  function flat (rec : sb_rec_t) return sb_vec_t is
  begin

    return std_logic_vector(rec.addr) & rec.data;

  end function flat;

  function unflat (arg : sb_vec_t) return sb_rec_t is

    variable r : sb_rec_t;

  begin

    r.data := arg(c_MEM_WIDTH - 1 downto 0);
    r.addr := unsigned(arg(arg'left downto c_MEM_WIDTH));
    return r;

  end function unflat;

  -- write aligned to memory width
  procedure write_aligned (
    signal addr      : out unsigned;
    signal data      : out std_logic_vector;
    constant c_ratio : positive
  ) is

    variable v_addr : addr'subtype;
    variable v_data : data'subtype;

  begin

    v_addr := to_unsigned(GetRandPoint(acov), addr'length);
    addr   <= v_addr;
    v_data := v_rv.randslv(data'length);
    data   <= v_data;
    wait for 1 ns;

    for i in 0 to c_ratio - 1 loop
      v_mem(to_integer(v_addr) * c_ratio + i) := v_data(v_data'left - (i * c_MEM_WIDTH) downto
                                                        (v_data'length - (i + 1) * c_MEM_WIDTH));
    end loop;

  end procedure write_aligned;

  -- read aligned to memory width
  procedure read_aligned (
    signal addr      : in unsigned;
    signal data      : in std_logic_vector;
    constant c_ratio : positive
  ) is

    variable v_data : data'subtype;

  begin

    for i in 0 to c_ratio - 1 loop
      v_data(data'left - (i * c_MEM_WIDTH) downto
      (data'length - (i + 1) * c_MEM_WIDTH)) := v_mem(to_integer(addr) * c_ratio + i);
    end loop;

    check(v_data = data, "Read Mismatch! at "&to_hstring(addr)&" Got "&to_hstring(data)&" exp "&to_hstring(v_data));

  end procedure read_aligned;

begin

  osvvm.TbUtilPkg.CreateClock(clka, c_ACLK_PERIOD);
  osvvm.TbUtilPkg.CreateClock(clkb, c_BCLK_PERIOD);

  dut : entity colibri.true_dpram
    generic map (
      g_A_ADDR_WIDTH => c_A_ADDR_W,
      g_B_ADDR_WIDTH => c_B_ADDR_W,
      g_A_DATA_WIDTH => g_A_DATA_WIDTH,
      g_B_DATA_WIDTH => g_B_DATA_WIDTH,
      g_N_WORDS      => c_N_WORDS,
      g_WRITE_FIRST  => g_WRITE_FIRST
    )
    port map (
      clka_i  => clka,
      clkb_i  => clkb,
      wra_i   => wra,
      wrb_i   => wrb,
      addra_i => addra,
      addrb_i => addrb,
      dataa_i => dataa,
      datab_i => datab,
      dataa_o => qa,
      datab_o => qb
    );

  proc_seq : process is
  begin

    test_runner_setup(runner, RUNNER_CFG);
    info("Starting OSVVM");
    --- OSVVM SETUP ---
    --
    acov <= NewID("ACov");
    wait for 0 ns;
    AddBins(acov, 1, GenBin(0, c_N_WORDS - 1));
    -- Set up coverage v_bins
    v_bin1.AddBins("write_a", 1, ONE_BIN);
    v_bin2.AddBins("read_a", 1, ONE_BIN);
    v_bin3.AddBins("write_b", 1, ONE_BIN);
    v_bin4.AddBins("read_b", 1, ONE_BIN);

    osvvm.TbUtilPkg.WaitForClock(clka, 1);

    loop
      wait for 1 ns;
      exit when
          IsCovered(acov);
    end loop;

    info("Coverage goals met!");

    osvvm.TbUtilPkg.WaitForClock(clka, 1);
    -- Print coverage data
    v_bin1.WriteBin;
    v_bin2.WriteBin;
    v_bin3.WriteBin;
    v_bin4.WriteBin;

    test_runner_cleanup(runner);

  end process proc_seq;

  proc_ram_model_a : process is
  begin

    osvvm.TbUtilPkg.WaitForClock(clka, 4);

    loop
      wra   <= '0';
      addra <= to_unsigned(GetRandPoint(acov) * c_A_RATIO, addra'length);

      if (not wrb) then
        if (v_rv.RandSlv(1)(1)) then
          osvvm.TbUtilPkg.WaitForClock(clka, 1);
          wait for 1 ns;
          info("reada "&to_hstring(addra)&" -> "&to_hstring(qa));
          read_aligned(addra, qa, c_A_RATIO);
          v_bin2.ICover(1);
        elsif (v_rv.RandSlv(1)(1)) then
          wra <= '1';
          write_aligned(addra, dataa, c_A_RATIO);
          wait for 1 ns;
          info("writea "&to_hstring(addra)&" -> "&to_hstring(dataa));
          osvvm.TbUtilPkg.WaitForClock(clka, 1);
          wra <= '0';
          v_bin1.ICover(1);
        end if;

        ICover(acov, to_integer(addra) / c_A_RATIO);
      end if;

      osvvm.TbUtilPkg.WaitForClock(clka, v_rv.randInt(1,6));

    end loop;

  end process proc_ram_model_a;

  proc_ram_model_b : process is
  begin

    osvvm.TbUtilPkg.WaitForClock(clkb, 4);

    loop
      wrb   <= '0';
      addrb <= to_unsigned(GetRandPoint(acov) * c_B_RATIO, addrb'length);

      if (not wra) then
        if (v_rv.RandSlv(1)(1)) then
          osvvm.TbUtilPkg.WaitForClock(clkb, 1);
          wait for 1 ns;
          info("readb "&to_hstring(addrb)&" -> "&to_hstring(qb));
          read_aligned(addrb, qb, c_B_RATIO);
          v_bin4.ICover(1);
        elsif (v_rv.RandSlv(1)(1)) then
          wrb <= '1';
          write_aligned(addrb, datab, c_B_RATIO);
          wait for 1 ns;
          info("writeb "&to_hstring(addrb)&" -> "&to_hstring(datab));
          osvvm.TbUtilPkg.WaitForClock(clkb, 1);
          wrb <= '0';
          v_bin3.ICover(1);
        end if;
        ICover(acov, to_integer(addrb) / c_B_RATIO);
      end if;

      osvvm.TbUtilPkg.WaitForClock(clkb, v_rv.randInt(1,6));

    end loop;

  end process proc_ram_model_b;

  test_runner_watchdog(runner, 100 us);

end architecture sim;
