-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;

library osvvm;
  use osvvm.randompkg.all;
  use osvvm.coveragepkg.all;

entity stream_to_wbm_tb is
  generic (
    RUNNER_CFG : string
  );
end entity stream_to_wbm_tb;

architecture tb of stream_to_wbm_tb is

  -- OSSVM vars
  shared variable v_rv       : randomptype;
  shared variable v_wr, v_rd : covptype;

  -- Clock period
  constant c_CLK_PERIOD    : time    := 5 ns;
  constant c_MEM_BYTES     : natural := 4 * 16;
  constant c_HDR_WIDTH     : natural := 8;
  constant c_WB_ADDR_WIDTH : natural := 32;
  constant c_WB_DATA_WIDTH : natural := 32;
  constant c_STREAM_WIDTH  : natural := c_HDR_WIDTH + c_WB_DATA_WIDTH;
  -- stream constants
  constant c_CMD_ADDR      : std_logic_vector(3 downto 0) := x"1"; --!  ADDRESS command
  constant c_CMD_RDATA     : std_logic_vector(3 downto 0) := x"2"; --! READ DATA command
  constant c_CMD_WDATA     : std_logic_vector(3 downto 0) := x"3"; --! WRITE DATA command
  constant c_CMD_ACK       : std_logic_vector(3 downto 0) := x"1"; --! CMD ACKNOWLEDGED command

  -- Generics
  -- Ports
  signal clk        : std_logic := '1';
  signal reset      : std_logic := '1';
  signal snk_data   : std_logic_vector(c_STREAM_WIDTH - 1 downto 0);
  signal snk_valid  : std_logic;
  signal snk_ready  : std_logic;
  signal src_data   : std_logic_vector(c_STREAM_WIDTH - 1 downto 0);
  signal src_valid  : std_logic;
  signal src_ready  : std_logic;
  signal wb_adr     : unsigned(c_WB_DATA_WIDTH - 1 downto 0);
  signal wb_adr_slv : std_logic_vector(c_WB_DATA_WIDTH - 1 downto 0);
  signal wb_wdat    : std_logic_vector(c_WB_DATA_WIDTH - 1 downto 0);
  signal wb_rdat    : std_logic_vector(c_WB_DATA_WIDTH - 1 downto 0);
  signal wb_we      : std_logic;
  signal wb_sel     : std_logic_vector(3 downto 0);
  signal wb_stb     : std_logic;
  signal wb_cyc     : std_logic;
  signal wb_ack     : std_logic;
  signal wb_err     : std_logic := '0';

  -- BFMs
  -- streaming write
  constant MASTER_AXI_STREAM : axi_stream_master_t := new_axi_stream_master(
                                                                            data_length => c_STREAM_WIDTH
   );
  constant MASTER_STREAM     : stream_master_t     := as_stream(MASTER_AXI_STREAM);
  -- streaming read
  constant SLAVE_AXI_STREAM  : axi_stream_slave_t := new_axi_stream_slave(
                                                                          data_length => c_STREAM_WIDTH
   );
  constant SLAVE_STREAM      : stream_slave_t     := as_stream(SLAVE_AXI_STREAM);
  -- wishbone memory slave
  constant MEMORY            : memory_t         := new_memory;
  constant BUF               : buffer_t         := allocate(MEMORY, c_MEM_BYTES);
  constant WISHBONE_SLAVE    : wishbone_slave_t :=
    new_wishbone_slave(MEMORY                 => MEMORY,
                       ack_high_probability   => 1.0,
                       stall_high_probability => 0.0
                     );

  signal mem_ready : std_logic := '0';

  type mem_t is array (0 to 15) of std_logic_vector(c_WB_DATA_WIDTH - 1 downto 0);

  shared variable ram_cosim : mem_t     := (others => (others => '0'));
  signal          wr_cosim  : std_logic := '0';
  signal          rd_cosim  : std_logic := '0';

begin

  -- initialize memory
  proc_init_mem : process is

    variable v_addr : std_logic_vector(c_WB_DATA_WIDTH - 1 downto 0);
    variable v_data : std_logic_vector(c_WB_DATA_WIDTH - 1 downto 0);
    variable v_ret  : std_logic_vector(c_WB_DATA_WIDTH - 1 downto 0);

    procedure memop (
      wr            : in    boolean;
      variable addr : in    std_logic_vector(c_WB_ADDR_WIDTH - 1 downto 0);
      variable data : inout std_logic_vector(c_WB_DATA_WIDTH - 1 downto 0)
    ) is

      -- Command header constants
      constant c_RD_HDR  : std_logic_vector(c_HDR_WIDTH - 1 downto 0) := 4x"0" & c_CMD_RDATA;
      constant c_WR_HDR  : std_logic_vector(c_HDR_WIDTH - 1 downto 0) := 4x"0" & c_CMD_WDATA;
      constant c_ADR_HDR : std_logic_vector(c_HDR_WIDTH - 1 downto 0) := 4x"0" & c_CMD_ADDR;

      -- Internal variables
      variable v_tmp : std_logic_vector(c_STREAM_WIDTH - 1 downto 0);

    begin

      -- Push address
      info("Push addr");
      push_stream(net, MASTER_STREAM,  c_ADR_HDR & addr);

      -- Acknowledge address data
      pop_stream(net, SLAVE_STREAM, v_tmp);

      info("Acknowledge address -> " & to_hstring(v_tmp));

      -- Push read/write command header
      if (wr) then
        info("Push write ");

        push_stream(net, MASTER_STREAM, c_WR_HDR & data);
      else
        info("Push read ");
        push_stream(net,  MASTER_STREAM, c_RD_HDR & data);
      end if;

      pop_stream(net, SLAVE_STREAM, v_tmp);

      info("Acknowledge response data -> "& to_hstring(v_tmp));

      data := v_tmp(c_WB_DATA_WIDTH - 1 downto 0);

    end procedure memop;

  begin

    wait until reset = '0';

    for k in 0 to 15 loop
      -- write request
      v_addr       := std_logic_vector(to_unsigned(k * 4, 32));
      v_data       := v_rv.RandSlv(v_data'length);
      info("master: INIT "&to_hstring(v_addr)&"->"&to_hstring(v_data));
      memop(true, v_addr, v_data);
      ram_cosim(k) := v_data;
      wait for c_CLK_PERIOD;

    end loop;

    wait for 1 us;
    info("master: MEM INIT COMPLETE");
    info("---------------------------------------------------");
    info("---------------------------------------------------");
    info("---------------------------------------------------");
    mem_ready <= '1';
    wait until reset = '1';

  end process proc_init_mem;

  -- Generate random transaction
  proc_write : process is

    variable v_addr  : std_logic_vector(c_WB_DATA_WIDTH - 1 downto 0);
    variable v_data  : std_logic_vector(c_WB_DATA_WIDTH - 1 downto 0);
    variable v_adr32 : integer;
    variable v_ret   : std_logic_vector(c_WB_DATA_WIDTH - 1 downto 0);

    procedure memop (
      wr            : in    boolean;
      variable addr : in    std_logic_vector(c_WB_ADDR_WIDTH - 1 downto 0);
      variable data : inout std_logic_vector(c_WB_DATA_WIDTH - 1 downto 0)
    ) is

      -- Command header constants
      constant c_RD_HDR  : std_logic_vector(c_HDR_WIDTH - 1 downto 0) := 4x"0" & c_CMD_RDATA;
      constant c_WR_HDR  : std_logic_vector(c_HDR_WIDTH - 1 downto 0) := 4x"0" & c_CMD_WDATA;
      constant c_ADR_HDR : std_logic_vector(c_HDR_WIDTH - 1 downto 0) := 4x"0" & c_CMD_ADDR;

      -- Internal variables
      variable v_tmp : std_logic_vector(c_STREAM_WIDTH - 1 downto 0);

    begin

      -- Push address
      info("Push addr");
      push_stream(net, MASTER_STREAM,  c_ADR_HDR & addr);

      -- Acknowledge address data
      pop_stream(net, SLAVE_STREAM, v_tmp);

      info("Acknowledge address -> " & to_hstring(v_tmp));

      -- Push read/write command header
      if (wr) then
        info("Push write ");

        push_stream(net, MASTER_STREAM, c_WR_HDR & data);
      else
        info("Push read ");
        push_stream(net,  MASTER_STREAM, c_RD_HDR & data);
      end if;

      pop_stream(net, SLAVE_STREAM, v_tmp);

      info("Acknowledge response data -> "& to_hstring(v_tmp));

      data := v_tmp(c_WB_DATA_WIDTH - 1 downto 0);

    end procedure memop;
  begin

    wait until reset = '0';

    loop

      if (not reset and mem_ready) then
        v_adr32 := v_rv.RandInt(15);
        v_addr  := std_logic_vector(to_unsigned(v_adr32 * 4, 32));
        if (v_rv.RandSlv(1)(1)) then
          -- WRITE
          wr_cosim           <= '1';
          v_data             := v_rv.RandSlv(v_data'length);
          ram_cosim(v_adr32) := v_data;
          info("master: WR "&to_hstring(v_addr)&"->"&to_hstring(v_data));
          memop(true, v_addr, v_data);
          v_wr.ICover(v_adr32);
          wait for 5 * c_CLK_PERIOD;
          wr_cosim           <= '0';
        else
          rd_cosim <= '1';
          --  READ
          memop(false, v_addr, v_data);
          info("master: RD "&to_hstring(v_addr)&"->"&to_hstring(v_data));
          check(v_data = ram_cosim(v_adr32), "data mismatch!! got "& to_hstring(v_data) & " /exp "& to_hstring(ram_cosim(v_adr32)));
          v_rd.ICover(v_adr32);
          wait for 5 * c_CLK_PERIOD;
          rd_cosim <= '0';
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

  ----------------------- entities ----------------------------
  stream_to_wbm_inst : entity colibri.stream_to_wbm

    port map (
      clk_i       => clk,
      reset_i     => reset,
      snk_data_i  => snk_data,
      snk_valid_i => snk_valid,
      snk_ready_o => snk_ready,
      src_data_o  => src_data,
      src_valid_o => src_valid,
      wb_adr_o    => wb_adr,
      wb_dat_i    => wb_rdat,
      wb_dat_o    => wb_wdat,
      wb_we_o     => wb_we,
      wb_sel_o    => wb_sel,
      wb_stb_o    => wb_stb,
      wb_cyc_o    => wb_cyc,
      wb_ack_i    => wb_ack,
      wb_err_i    => wb_err
    );

  clk <= not clk after c_CLK_PERIOD / 2;

  axi_stream_slave_inst : entity vunit_lib.axi_stream_slave
    generic map (
      SLAVE => slave_axi_stream
    )
    port map (
      aclk     => clk,
      areset_n => not reset,
      tvalid   => src_valid,
      tready   => src_ready,
      tdata    => src_data
    );

  axi_stream_master_inst : entity vunit_lib.axi_stream_master
    generic map (
      MASTER => master_axi_stream
    )
    port map (
      aclk     => clk,
      areset_n => not reset,
      tvalid   => snk_valid,
      tready   => snk_ready,
      tdata    => snk_data
    );

  wb_slave : entity vunit_lib.wishbone_slave
    generic map (
      WISHBONE_SLAVE => wishbone_slave
    )
    port map (
      clk   => clk,
      adr   => wb_adr_slv,
      dat_i => wb_wdat,
      dat_o => wb_rdat,
      sel   => wb_sel,
      cyc   => wb_cyc,
      stb   => wb_stb,
      we    => wb_we,
      stall => open,
      ack   => wb_ack
    );

  wb_adr_slv <= std_logic_vector(wb_adr);
  test_runner_watchdog(runner, 50 ms);

end architecture tb;
