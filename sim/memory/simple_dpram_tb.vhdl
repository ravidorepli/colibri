
--! @file simple_dpram_tb.vhdl
--! @brief Simple Dual-Port RAM Testbench
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 04-03-2024 Created
--! @version 0.1
--! @version 0.2
--! @copyright CERN 2025
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.mem.all;

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
  use osvvm.scoreboardpkg_slv.all;

library colibri;
  context colibri.common;

entity simple_dpram_tb is
  generic (
    RUNNER_CFG     : string;
    -- Set these to test asymmetry
    g_A_DATA_WIDTH : positive := 32;
    g_B_DATA_WIDTH : positive := 8;
    g_IMPL_STYLE   : natural  := 0
  );
end entity simple_dpram_tb;

architecture sim of simple_dpram_tb is

  constant c_N_WORDS : positive := 64; -- Depth in terms of the LARGEST width

  -- Address Width Calculations
  constant c_MAX_W     : positive := maximum(g_A_DATA_WIDTH, g_B_DATA_WIDTH);
  constant c_WR_ADDR_W : natural  := log2ceil(c_N_WORDS * (c_MAX_W / g_A_DATA_WIDTH));
  constant c_RD_ADDR_W : natural  := log2ceil(c_N_WORDS * (c_MAX_W / g_B_DATA_WIDTH));
  constant c_RATIO     : positive := c_MAX_W / minimum(g_A_DATA_WIDTH, g_B_DATA_WIDTH);

  signal wrclk, rdclk : std_logic                          := '1';
  signal wren,  rden  : std_logic                          := '0';
  signal wraddr       : unsigned(c_WR_ADDR_W - 1 downto 0) := (others => '0');
  signal rdaddr       : unsigned(c_RD_ADDR_W - 1 downto 0) := (others => '0');
  signal wrdata       : std_logic_vector(g_A_DATA_WIDTH - 1 downto 0);
  signal rddata       : std_logic_vector(g_B_DATA_WIDTH - 1 downto 0);

  shared variable v_rv   : randomptype;
  signal          sb     : scoreboardidtype := NewID("RAM_SB");
  signal          done   : std_logic        := '0';
  signal          wrdone : std_logic        := '0';

  subtype sb_vec_t is std_logic_vector(c_WR_ADDR_W + G_A_DATA_WIDTH - 1 downto 0);

  -- Scoreboard Record: Stores what was written exactly
  type sb_rec_t is record
    addr : unsigned(c_WR_ADDR_W - 1 downto 0);
    data : std_logic_vector(G_A_DATA_WIDTH - 1 downto 0);
  end record sb_rec_t;

  function flat (rec : sb_rec_t) return sb_vec_t is
  begin

    return std_logic_vector(rec.addr) & rec.data;

  end function flat;

  function unflat (arg : sb_vec_t) return sb_rec_t is

    variable r : sb_rec_t;

  begin

    r.data := arg(G_A_DATA_WIDTH - 1 downto 0);
    r.addr := unsigned(arg(arg'left downto G_A_DATA_WIDTH));
    return r;

  end function unflat;

begin

  osvvm.TbUtilPkg.CreateClock(wrclk, 7 ns);
  osvvm.TbUtilPkg.CreateClock(rdclk, 5 ns);

  gen_impl : case g_IMPL_STYLE generate

    when 1 => -- use quartus

      dut : entity colibri.simple_dpram
        generic map (
          g_A_DATA_WIDTH => g_A_DATA_WIDTH,
          g_B_DATA_WIDTH => g_B_DATA_WIDTH,
          g_N_WORDS      => c_N_WORDS,
          g_A_ADDR_WIDTH => c_WR_ADDR_W,
          g_B_ADDR_WIDTH => c_RD_ADDR_W,
          g_IMPL_STYLE   => QUARTUS
        )
        port map (
          wrclk_i  => wrclk,
          rdclk_i  => rdclk,
          wren_i   => wren,
          rden_i   => rden,
          wraddr_i => wraddr,
          rdaddr_i => rdaddr,
          wrdata_i => wrdata,
          rddata_o => rddata
        );

    when others =>

      dut : entity colibri.simple_dpram
        generic map (
          g_A_DATA_WIDTH => g_A_DATA_WIDTH,
          g_B_DATA_WIDTH => g_B_DATA_WIDTH,
          g_N_WORDS      => c_N_WORDS,
          g_A_ADDR_WIDTH => c_WR_ADDR_W,
          g_B_ADDR_WIDTH => c_RD_ADDR_W
        )
        port map (
          wrclk_i  => wrclk,
          rdclk_i  => rdclk,
          wren_i   => wren,
          rden_i   => rden,
          wraddr_i => wraddr,
          rdaddr_i => rdaddr,
          wrdata_i => wrdata,
          rddata_o => rddata
        );

  end generate gen_impl;

  proc_seq : process is
  begin

    test_runner_setup(runner, RUNNER_CFG);
    osvvm.TbUtilPkg.WaitForClock(wrclk, 10);
    osvvm.TbUtilPkg.waitforlevel(done, '1');
    osvvm.TbUtilPkg.WaitForClock(wrclk, 1);
    test_runner_cleanup(runner);

  end process proc_seq;

  proc_ram_writer : process is

    variable v_rec : sb_rec_t;

  begin

    wrdone <= '0';

    osvvm.TbUtilPkg.WaitForClock(wrclk, 5);

    for i in 0 to c_N_WORDS - 1 loop
      wren       <= '1';
      v_rec.addr := to_unsigned(i, c_WR_ADDR_W);
      v_rec.data := v_rv.RandSlv(g_A_DATA_WIDTH);
      wraddr     <= v_rec.addr;
      wrdata     <= v_rec.data;
      push(sb, flat(v_rec));
      osvvm.TbUtilPkg.WaitForClock(wrclk, 1);
      wren       <= '0';
      osvvm.TbUtilPkg.WaitForClock(wrclk, v_rv.RandInt(0, 1));
    end loop;

    wrdone <= '1';
    wait;

  end process proc_ram_writer;

  proc_ram_reader : process is

    variable v_rec           : sb_rec_t;
    variable v_vec           : sb_vec_t;
    variable v_expected_full : std_logic_vector(g_B_DATA_WIDTH - 1 downto 0);

  begin

    osvvm.TbUtilPkg.WaitForClock(rdclk, 20);
    osvvm.TbUtilPkg.waitforlevel(wrdone, '1');

    loop
      v_expected_full := (others => '0');

      if (g_B_DATA_WIDTH >= g_A_DATA_WIDTH) then
        -----------------------------------------------------------
        -- CASE 1: WRITE SMALL, READ LARGE
        -----------------------------------------------------------
        -- We must pop 4 writes to verify 1 large read
        for i in 0 to c_RATIO - 1 loop

          v_vec := pop(sb);
          v_rec := unflat(v_vec);

          -- compose
          v_expected_full(g_B_DATA_WIDTH - (i * g_A_DATA_WIDTH) - 1 downto g_B_DATA_WIDTH -  (i + 1) * g_A_DATA_WIDTH) := v_rec.data;

          -- Verify address alignment: Large address = Small address / Ratio
          if (i = 0) then
            rdaddr <= resize(v_rec.addr / c_RATIO, rdaddr'length);
          end if;
        end loop;

        rden <= '1';
        osvvm.TbUtilPkg.WaitForClock(rdclk, 1);
        wait for 1 ns;
        info("Read -> "& to_hstring(rdaddr) &": "&to_hstring(rddata));
        check
              (rddata = v_expected_full, "Read Large Mismatch at Addr: " & to_hstring(rdaddr) &
               " Got "&to_hstring(rddata)&" exp "&to_hstring(v_expected_full));
        rden <= '0';
      elsif (g_B_DATA_WIDTH < g_A_DATA_WIDTH) then
        -----------------------------------------------------------
        -- CASE 2: WRITE LARGE, READ SMALL
        -----------------------------------------------------------
        -- Pop 1 large write, perform 4 small reads
        v_vec := pop(sb);
        v_rec := unflat(v_vec);

        for i in 0 to c_RATIO - 1 loop
          rden                                         <= '1';
          rdaddr                                       <= resize((v_rec.addr * c_RATIO) + i, rdaddr'length);
          osvvm.TbUtilPkg.WaitForClock(rdclk, 1);
          wait for 1 ns;
          info("Read -> "& to_hstring(rdaddr) &": "&to_hstring(rddata));
          v_expected_full(g_B_DATA_WIDTH - 1 downto 0) :=
            v_rec.data(g_A_DATA_WIDTH - (i * g_B_DATA_WIDTH) - 1 downto g_A_DATA_WIDTH - ((i + 1) * g_B_DATA_WIDTH));
          check(rddata = v_expected_full(g_B_DATA_WIDTH - 1 downto 0),
                "Read Small Mismatch at Addr: " & to_hstring(rdaddr) &
                " Got "&to_hstring(rddata)&" exp "&to_hstring(v_expected_full));
          rden                                         <= '0';
        end loop;

      end if;

      osvvm.TbUtilPkg.WaitForClock(rdclk, 1);
      exit when osvvm.scoreboardpkg_slv.empty(sb);
    end loop;

    done <= '1';
    info("Read completed");
    wait;

  end process proc_ram_reader;

  test_runner_watchdog(runner, 100 us);

end architecture sim;
