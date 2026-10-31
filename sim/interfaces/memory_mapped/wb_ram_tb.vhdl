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

--
library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;

entity wb_ram_tb is
  generic (
    RUNNER_CFG : string
  );
end entity wb_ram_tb;

architecture bench of wb_ram_tb is

  -- OSSVM vars
  shared variable v_rv       : randomptype;
  shared variable v_wr, v_rd : covptype;

  -- Clock period
  constant c_CLK_PERIOD    : time := 5 ns;
  -- Generics
  constant c_N_WORDS       : positive := 16;
  constant c_WB_DATA_WIDTH : positive := 32;
  constant c_WB_ADDR_WIDTH : positive := 32;
  -- Ports
  signal clk               : std_logic := '1';
  signal reset             : std_logic := '1';
  signal wb_adr            : unsigned(c_WB_ADDR_WIDTH - 1 downto 0);
  signal wb_adr_slv        : std_logic_vector(c_WB_ADDR_WIDTH - 1 downto 0);
  signal wb_odat           : std_logic_vector(c_WB_DATA_WIDTH - 1 downto 0);
  signal wb_idat           : std_logic_vector(c_WB_DATA_WIDTH - 1 downto 0);
  signal wb_we             : std_logic;
  signal wb_sel            : std_logic_vector(c_WB_DATA_WIDTH / 8 - 1 downto 0);
  signal wb_stb            : std_logic;
  signal wb_cyc            : std_logic;
  signal wb_ack            : std_logic;
  signal wb_err            : std_logic;

  type mem_t is array (0 to 15) of std_logic_vector(31 downto 0);

  shared variable v_ram_cosim : mem_t := (others => (others => '0'));

  constant c_BUS_HANDLE : bus_master_t := new_bus(data_length => c_WB_DATA_WIDTH, address_length => c_WB_ADDR_WIDTH);

begin

  wb_ram_inst : entity colibri.wb_ram
    generic map (
      g_N_WORDS       => c_N_WORDS,
      g_WB_DATA_WIDTH => c_WB_DATA_WIDTH,
      g_WB_ADDR_WIDTH => c_WB_ADDR_WIDTH
    )
    port map (
      clk_i    => clk,
      reset_i  => reset,
      wb_adr_i => wb_adr,
      wb_dat_i => wb_odat,
      wb_dat_o => wb_idat,
      wb_we_i  => wb_we,
      wb_sel_i => wb_sel,
      wb_stb_i => wb_stb,
      wb_cyc_i => wb_cyc,
      wb_ack_o => wb_ack,
      wb_err_o => wb_err
    );

  -- Generate random transaction
  proc_write : process is

    variable v_addr  : std_logic_vector(31 downto 0);
    variable v_data  : std_logic_vector(31 downto 0);
    variable v_adr32 : integer;

  begin

    wait until reset = '0';
    info("start transactions");

    loop

      if (not reset) then
        v_adr32 := v_rv.RandInt(15);
        v_addr  := std_logic_vector(to_unsigned(v_adr32 * 4, 32));
        if (v_rv.RandSlv(1)(1)) then
          -- WRITE
          v_data               := v_rv.RandSlv(v_data'length);
          v_ram_cosim(v_adr32) := v_data;
          write_bus(net, c_BUS_HANDLE, v_addr, v_data);
          v_wr.ICover(v_adr32);
          info("master: WR "&to_hstring(v_addr)&"->"&to_hstring(v_data));
        else
          --  READ
          read_bus(net, c_BUS_HANDLE, v_addr, v_data);
          info("master: RD "&to_hstring(v_addr)&"->"&to_hstring(v_data));
          check(v_data = v_ram_cosim(v_adr32), "data mismatch");
          v_rd.ICover(v_adr32);
        end if;
      end if;

      wait for c_CLK_PERIOD;
      exit when v_wr.IsCovered and v_rd.IsCovered;
    end loop;

    wait;

  end process proc_write;

  proc_sequencer : process is
  begin

    ---------------- VUNIT SETUP ---------------
    test_runner_setup(runner, RUNNER_CFG);
    info("Starting OSVVM");

    --- OSVVM SETUP ---
    -- Set up coverage v_bins
    v_wr.AddBins("Write", GenBin(0,15));
    v_rd.AddBins("Read", GenBin(0,15));

    if run("coverage") then
      info("Starting the test");
      wait for c_CLK_PERIOD;
      reset <= '0';

      loop
        wait for c_CLK_PERIOD;
        exit when v_wr.IsCovered and v_rd.IsCovered;
      end loop;

      info("Coverage goals met!");
    end if;

    -- Print coverage data
    v_rd.WriteBin;
    v_wr.WriteBin;
    -- VUnit cleanup
    test_runner_cleanup(runner);

  end process proc_sequencer;

  dut : entity vunit_lib.wishbone_master
    generic map (
      BUS_HANDLE              => c_BUS_HANDLE,
      STROBE_HIGH_PROBABILITY => 1.0
    )
    port map (
      clk   => clk,
      adr   => wb_adr_slv,
      dat_i => wb_idat,
      dat_o => wb_odat,
      sel   => wb_sel,
      cyc   => wb_cyc,
      stb   => wb_stb,
      we    => wb_we,
      stall => '0',
      ack   => wb_ack
    );

  wb_sel <= (others => '1');
  wb_adr <= unsigned(wb_adr_slv);
  clk    <= not clk after c_CLK_PERIOD / 2;
  test_runner_watchdog(runner, 10 ms);

end architecture bench;
