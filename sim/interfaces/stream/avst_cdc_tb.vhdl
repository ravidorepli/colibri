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
  context vunit_lib.com_context;
  context vunit_lib.data_types_context;
  context vunit_lib.vc_context;

entity avst_cdc_tb is
  generic (
    RUNNER_CFG : string
  );
end entity avst_cdc_tb;

architecture bench of avst_cdc_tb is

  shared variable v_rv  : randomptype;
  signal          s_cov : coverageidtype;
  signal          sb    : scoreboardidtype := NewID("sb");

  -- Clock period
  constant c_SNK_CLK_PERIOD : time := 25 ns;
  constant c_SRC_CLK_PERIOD : time := 4 ns;
  -- Generics
  constant c_DATA_WIDTH     : positive := 16;
  -- Ports
  signal reset              : std_logic := '1';
  signal snk_clk            : std_logic := '1';
  signal src_clk            : std_logic := '1';
  signal snk_ready          : std_logic;
  signal snk_valid          : std_logic;
  signal snk_sop            : std_logic;
  signal snk_eop            : std_logic;
  signal snk_empty          : unsigned(log2ceil(c_DATA_WIDTH) - 1 downto 0);
  signal snk_data           : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal src_ready          : std_logic;
  signal src_valid          : std_logic;
  signal src_sop            : std_logic;
  signal src_eop            : std_logic;
  signal src_empty          : unsigned(log2ceil(c_DATA_WIDTH) - 1 downto 0);
  signal src_data           : std_logic_vector(c_DATA_WIDTH - 1 downto 0);

  -- avalon interfaces
  constant c_AVST_SRC_VVC  : avalon_source_t :=
    new_avalon_source(data_length => c_DATA_WIDTH, valid_high_probability => 0.3);
  constant c_MASTER_STREAM : stream_master_t := as_stream(c_AVST_SRC_VVC);

  constant c_AVST_SNK_VVC : avalon_sink_t  :=
    new_avalon_sink(data_length => c_DATA_WIDTH, ready_high_probability => 0.9);
  constant c_SLAVE_STREAM : stream_slave_t := as_stream(c_AVST_SNK_VVC);

  -- test vector
  constant c_TEST_SIZE : natural := c_DATA_WIDTH * 50;

  signal test_vec : std_logic_vector(c_TEST_SIZE - 1 downto 0);

begin

  osvvm.TbUtilPkg.CreateClock(snk_clk, c_SNK_CLK_PERIOD);

  osvvm.TbUtilPkg.CreateClock(src_clk, c_SRC_CLK_PERIOD);

  avst_cdc_inst : entity colibri.avst_cdc
    generic map (
      g_DATA_WIDTH => c_DATA_WIDTH
    )
    port map (
      reset_i     => reset,
      snk_clk_i   => snk_clk,
      src_clk_i   => src_clk,
      snk_ready_o => snk_ready,
      snk_valid_i => snk_valid,
      snk_sop_i   => snk_sop,
      snk_eop_i   => snk_eop,
      snk_empty_i => snk_empty,
      snk_data_i  => snk_data,
      src_ready_i => src_ready,
      src_valid_o => src_valid,
      src_sop_o   => src_sop,
      src_eop_o   => src_eop,
      src_empty_o => src_empty,
      src_data_o  => src_data
    );

  main : process is
  begin

    test_runner_setup(runner, RUNNER_CFG);
    s_cov <= NewID("data coverage");
    wait for 0 ns;
    AddBins(s_cov, 1, GenBin(0,(2**(c_DATA_WIDTH)), 16)); -- cover all bytes

    osvvm.TbUtilPkg.WaitForClock(snk_clk, 1);
    reset <= '0';

    while test_suite loop

      if run("test_alive") then
        info("Hello world test_alive");

        loop
          osvvm.TbUtilPkg.WaitForClock(snk_clk, 1);
          exit when IsCovered(s_cov);
        end loop;

        WriteBin(s_cov);
        test_runner_cleanup(runner);
      end if;

    end loop;

  end process main;

  proc_master : process is

    variable v_tmp : std_logic_vector(c_DATA_WIDTH - 1 downto 0);

  begin

    osvvm.TbUtilPkg.WaitForClock(snk_clk, 5);

    while true loop
      v_tmp := std_logic_vector(to_unsigned(GetRandPoint(s_cov), c_DATA_WIDTH));
      wait for 0 ns;
      push_stream(net, c_MASTER_STREAM, v_tmp);
      push(sb, v_tmp);
      info("Sent "&to_hstring(v_tmp));
      osvvm.TbUtilPkg.WaitForClock(snk_clk, 1);
    end loop;

  end process proc_master;

  proc_slave : process is

    variable v_tmp : std_logic_vector(c_DATA_WIDTH - 1 downto 0);

  begin

    osvvm.TbUtilPkg.WaitForClock(src_clk, 5);

    while true loop
      pop_stream(net, c_SLAVE_STREAM, v_tmp);
      check(sb, v_tmp);
      info("Received "&to_hstring(v_tmp));
      ICover(s_cov, to_integer(unsigned(v_tmp)));
      osvvm.TbUtilPkg.WaitForClock(snk_clk, 1);
    end loop;

  end process proc_slave;

  -- clk <= not clk after clk_period/2;

  avalon_source_vc : entity vunit_lib.avalon_source
    generic map (
      SOURCE => c_AVST_SRC_VVC
    )
    port map (
      clk   => snk_clk,
      valid => snk_valid,
      ready => snk_ready,
      sop   => snk_sop,
      eop   => snk_eop,
      data  => snk_data
    );

  avalon_sink_vc : entity vunit_lib.avalon_sink
    generic map (
      SINK => c_AVST_SNK_VVC
    )
    port map (
      clk   => src_clk,
      valid => src_valid,
      ready => src_ready,
      sop   => src_sop,
      eop   => src_eop,
      data  => src_data
    );

  test_runner_watchdog(runner, 10 ms);

end architecture bench;
