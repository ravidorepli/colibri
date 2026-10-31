-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  context colibri.common;

library osvvm;
  use osvvm.randompkg.all;

--
library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;

entity cc_gearbox_loopback_tb is
  generic (
    RUNNER_CFG  : string;
    -- Generics
    g_A_WIDTH   : integer := 66;
    g_B_WIDTH   : integer := 64;
    g_TEST_SIZE : integer := 10
  );
end entity cc_gearbox_loopback_tb;

architecture bench of cc_gearbox_loopback_tb is

  -- OSSVM vars
  shared variable v_rv  : RandomPType;
  -- Clock period
  constant CLK_PERIOD   : time    := 5 ns;
  constant c_TEST_WORDS : integer := least_common_mult(g_A_WIDTH,g_B_WIDTH) /g_A_WIDTH * g_TEST_SIZE ;

  -- Ports
  signal clk       : std_logic := '1';
  signal gbx_clk   : std_logic := '1';
  signal reset     : std_logic := '1';
  signal snk_data  : std_logic_vector(g_A_WIDTH - 1 downto 0);
  signal snk_valid : std_logic;
  signal snk_ready : std_logic;
  signal gbx_data  : std_logic_vector(g_B_WIDTH - 1 downto 0);
  signal gbx_valid : std_logic;
  signal gbx_ready : std_logic;
  signal src_data  : std_logic_vector(g_A_WIDTH - 1 downto 0);
  signal src_valid : std_logic;
  signal src_ready : std_logic;

  signal test_vec : snk_data'subtype;

  -- BFMs
  constant MIN_STALL_CYCLES    : natural        := 1;
  constant MAX_STALL_CYCLES    : natural        := 8;
  constant MASTER_STALL_CONFIG : stall_config_t := new_stall_config(stall_probability => 0.5, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);
  constant SLAVE_STALL_CONFIG  : stall_config_t := new_stall_config(stall_probability => 0.5, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);

  -- streaming write
  constant MASTER_AXI_STREAM : axi_stream_master_t := new_axi_stream_master(
                                                                            data_length => g_A_WIDTH,
     STALL_CONFIG                                                                       => MASTER_STALL_CONFIG
   );
  constant MASTER_STREAM     : stream_master_t     := as_stream(MASTER_AXI_STREAM);
  -- streaming read
  constant SLAVE_AXI_STREAM  : axi_stream_slave_t := new_axi_stream_slave(
                                                                          data_length => g_A_WIDTH,
     STALL_CONFIG                                                                     => SLAVE_STALL_CONFIG
   );
  constant SLAVE_STREAM      : stream_slave_t     := as_stream(SLAVE_AXI_STREAM);
  signal   rd_event          : event_t            := new_event("reading complete");

begin

  gearbox_a_inst : entity colibri.cc_gearbox
    generic map (
      g_INPUT_WIDTH  => g_A_WIDTH,
      g_OUTPUT_WIDTH => g_B_WIDTH
    )
    port map (
      snk_clk_i   => clk,
      src_clk_i   => gbx_clk,
      snk_reset_i => reset,
      snk_data_i  => snk_data,
      snk_valid_i => snk_valid,
      snk_ready_o => snk_ready,
      src_data_o  => gbx_data,
      src_valid_o => gbx_valid,
      src_ready_i => gbx_ready
    );

  gearbox_b_inst : entity colibri.cc_gearbox
    generic map (
      g_INPUT_WIDTH  => g_B_WIDTH,
      g_OUTPUT_WIDTH => g_A_WIDTH
    )
    port map (
      snk_clk_i   => gbx_clk,
      src_clk_i   => clk,
      snk_reset_i => reset,
      snk_data_i  => gbx_data,
      snk_valid_i => gbx_valid,
      snk_ready_o => gbx_ready,
      src_data_o  => src_data,
      src_valid_o => src_valid,
      src_ready_i => src_ready
    );

  proc_write : process is
  begin

    wait until not reset;

    for i in 0 to c_TEST_WORDS - 1 loop
      push_stream(net, MASTER_STREAM, test_vec);
      wait for CLK_PERIOD;

    end loop;

    info("write complete");
  end process proc_write;

  proc_read : process is

    variable v_out : src_data'subtype;

  begin

    wait until not reset;

    for i in 0 to c_TEST_WORDS - 1 loop
      pop_stream(net, SLAVE_STREAM, v_out);
      check(v_out = test_vec, "data mismatch: "&to_hstring(v_out)&" exp "& to_hstring(test_vec));
      wait for CLK_PERIOD;
    end loop;

    wait for 10 ns;
    info("read complete");
    notify(rd_event);

  end process proc_read;

  main : process is
  begin

    test_runner_setup(runner, runner_cfg);
    test_vec <= v_rv.RandSlv(g_A_WIDTH);
    wait for 3 * CLK_PERIOD;
    reset    <= '0';
    wait for 3 * CLK_PERIOD;

    if run("loopback") then
      info("Testing cc_gearbox_loopback");
      wait for 3 * CLK_PERIOD;
      wait until is_active(rd_event);
      wait for 3 * CLK_PERIOD;
    end if;

    test_runner_cleanup(runner);

  end process main;

  clk     <= not clk after CLK_PERIOD / 2;
  gbx_clk <= not gbx_clk after CLK_PERIOD / 7;

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

  test_runner_watchdog(runner, 300 us);

end architecture bench;
