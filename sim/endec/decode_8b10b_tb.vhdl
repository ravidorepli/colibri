-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;

library osvvm;
  context osvvm.osvvmcontext;
  use osvvm.randompkg.all;
  use osvvm.coveragepkg.all;

--
library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;
--==================================================================================================
--! @brief 8b/10b decoding Test Bench
--! @details
--!
--! This testbench uses two stream VVCs.
--! COVERAGE:
--! All possible 10b values are sent, valid Dxx.y and Kxx.y words are tested using constrained random coverage.

-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity decode_8b10b_tb is
  generic (
    RUNNER_CFG : string
  );
end entity decode_8b10b_tb;

architecture bench of decode_8b10b_tb is

  -- Clock period
  constant c_CLK_PERIOD        : time := 5 ns;
  -- OSVVM coverage
  shared variable v_rv         : randomptype;
  signal          s_cov        : coverageidtype;
  -- BFMs
  constant MIN_STALL_CYCLES    : natural        := 1;
  constant MAX_STALL_CYCLES    : natural        := 8;
  constant MASTER_STALL_CONFIG : stall_config_t := new_stall_config(stall_probability => 0.5, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);
  signal   reset               : std_logic      := '1';

  -- Ports
  signal clk       : std_logic := '1';
  signal src_data  : std_logic_vector(8 downto 0);
  signal src_valid : std_logic;
  signal snk_data  : std_logic_vector(9 downto 0);
  signal snk_valid : std_logic;

  -- streaming write
  constant MASTER_AXI_STREAM : axi_stream_master_t := new_axi_stream_master(
                                                                            data_length => snk_data'length,
     STALL_CONFIG                                                                       => MASTER_STALL_CONFIG
   );
  constant MASTER_STREAM     : stream_master_t     := as_stream(MASTER_AXI_STREAM);
  -- streaming read
  constant SLAVE_AXI_STREAM  : axi_stream_slave_t := new_axi_stream_slave(
                                                                          data_length => src_data'length
   );
  constant SLAVE_STREAM      : stream_slave_t     := as_stream(SLAVE_AXI_STREAM);

begin

  decode_8b10b_inst : entity colibri.decode_8b10b
    port map (
      clk_i         => clk,
      snk_data_i    => snk_data,
      snk_valid_i   => snk_valid,
      src_data_o    => src_data(7 downto 0),
      src_control_o => src_data(8),
      src_valid_o   => src_valid
    );

  proc_seq : process is

    variable v_data  : snk_data'subtype;
    variable v_recv  : src_data'subtype;
    variable v_count : positive;

  begin

    test_runner_setup(runner, RUNNER_CFG);
    info("Starting OSVVM");

    osvvm.TbUtilPkg.WaitForClock(clk, 1);
    reset <= '0'; -- reset VVCs
    osvvm.TbUtilPkg.WaitForClock(clk, 1);

    if run("coverage") then
      s_cov <= NewID("valid coverage");
      wait for 0 ns;
      AddBins(s_cov, "DATA", GenBin(0, 255));
      AddBins(s_cov, "K28.0", GenBin(284)); -- k '1' val 1C
      AddBins(s_cov, "K28.1", GenBin(316)); -- k '1' val 3C
      AddBins(s_cov, "K28.2", GenBin(348)); -- k '1' val 5C
      AddBins(s_cov, "K28.3", GenBin(380)); -- k '1' val 7C
      AddBins(s_cov, "K28.4", GenBin(412)); -- k '1' val 9C
      AddBins(s_cov, "K28.5", GenBin(444)); -- k '1' val BC
      AddBins(s_cov, "K28.6", GenBin(476)); -- k '1' val DC
      AddBins(s_cov, "K23.7", GenBin(503)); -- k '1' val F7
      AddBins(s_cov, "K27.7", GenBin(507)); -- k '1' val FB
      AddBins(s_cov, "K28.7", GenBin(508)); -- k '1' val FC
      AddBins(s_cov, "K29.7", GenBin(509)); -- k '1' val FD
      AddBins(s_cov, "K30.7", GenBin(510)); -- k '1' val FE
      wait for 0 ns;

      -- test all possible values
      for i in 0 to 2 ** (v_data'length) - 1 loop
        v_data := std_logic_vector(to_unsigned(i, v_data'length));
        wait for 0 ns;
        push_stream(net, MASTER_STREAM, v_data);
      end loop;

      -- wait for coverage
      loop
        osvvm.TbUtilPkg.WaitForClock(clk, 1);
        exit when IsCovered(s_cov);
      end loop;

      WriteBin(s_cov);
    end if;

    test_runner_cleanup(runner);

  end process proc_seq;

  -- receive valid data and populate coverage
  proc_recv : process is

    variable v_recv : src_data'subtype;

  begin

    wait until reset = '0';

    loop
      pop_stream(net, SLAVE_STREAM, v_recv);
      ICover(s_cov, to_integer(unsigned(v_recv)));
      exit when IsCovered(s_cov);
    end loop;

  end process proc_recv;

  test_runner_watchdog(runner, 10 ms);

  axi_stream_slave_inst : entity vunit_lib.axi_stream_slave
    generic map (
      SLAVE => slave_axi_stream
    )
    port map (
      aclk     => clk,
      areset_n => not reset,
      tvalid   => src_valid,
      tready   => open,
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
      tready   => '1',
      tdata    => snk_data
    );

  osvvm.TbUtilPkg.CreateClock(clk, c_CLK_PERIOD);

end architecture bench;
