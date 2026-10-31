-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;

library osvvm;
  use osvvm.randompkg.all;

--
library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;

entity cc_gearbox_down_thr_tb is
  generic (
    RUNNER_CFG : string
  );
end entity cc_gearbox_down_thr_tb;

architecture bench of cc_gearbox_down_thr_tb is

  -- OSSVM vars
  shared variable v_rv    : RandomPType;
  -- Clock period
  constant SNK_CLK_PERIOD : time := 5 ns;
  constant SRC_CLK_PERIOD : time := 5 ns;
  -- Generics
  constant G_INPUT_WIDTH  : positive := 10;
  constant G_OUTPUT_WIDTH : positive := 8;
  constant G_BUFFER_WORDS : positive := 10;
  -- Ports
  signal snk_clk          : std_logic := '1';
  signal snk_reset        : std_logic := '1';
  signal src_clk          : std_logic := '1';
  signal snk_data         : std_logic_vector(G_INPUT_WIDTH - 1 downto 0);
  signal snk_valid        : std_logic;
  signal snk_ready        : std_logic;
  signal src_data         : std_logic_vector(G_OUTPUT_WIDTH - 1 downto 0);
  signal src_valid        : std_logic;
  signal src_ready        : std_logic;

  -- BFMs
  constant MIN_STALL_CYCLES    : natural        := 1;
  constant MAX_STALL_CYCLES    : natural        := 8;
  constant MASTER_STALL_CONFIG : stall_config_t := new_stall_config(stall_probability => 0.0, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);
  constant SLAVE_STALL_CONFIG  : stall_config_t := new_stall_config(stall_probability => 0.0, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);

  -- streaming write
  constant MASTER_AXI_STREAM : axi_stream_master_t := new_axi_stream_master(
                                                                            data_length => G_INPUT_WIDTH,
     STALL_CONFIG                                                                       => MASTER_STALL_CONFIG
   );
  constant MASTER_STREAM     : stream_master_t     := as_stream(MASTER_AXI_STREAM);
  -- streaming read
  constant SLAVE_AXI_STREAM  : axi_stream_slave_t := new_axi_stream_slave(
                                                                          data_length => G_OUTPUT_WIDTH,
     STALL_CONFIG                                                                     => SLAVE_STALL_CONFIG
   );
  constant SLAVE_STREAM      : stream_slave_t     := as_stream(SLAVE_AXI_STREAM);

  -- test vector
  constant TEST_SIZE   : positive  := least_common_mult(G_INPUT_WIDTH, G_OUTPUT_WIDTH) * G_BUFFER_WORDS * 5;
  signal   test_vec    : std_logic_vector(TEST_SIZE - 1 downto 0);
  signal   rd_complete : std_logic := '0';
  signal   rd_start    : std_logic := '0';
  signal   rd_event    : event_t   := new_event("reading complete");
  signal   en          : std_logic := '1';

begin

  cc_gearbox_down_inst : entity colibri.cc_gearbox
    generic map (
      g_INPUT_WIDTH  => g_INPUT_WIDTH,
      g_OUTPUT_WIDTH => g_OUTPUT_WIDTH,
      g_BUFFER_WORDS => g_BUFFER_WORDS
    )
    port map (
      snk_clk_i   => snk_clk,
      snk_reset_i => snk_reset,
      src_clk_i   => src_clk,
      snk_data_i  => snk_data,
      snk_valid_i => snk_valid,
      snk_ready_o => snk_ready,
      src_data_o  => src_data,
      src_valid_o => src_valid,
      src_ready_i => src_ready
    );

  proc_write : process is

    variable v_vec : test_vec'subtype;
    variable v_ptr : natural;

  begin

    wait until not snk_reset;
    v_vec := test_vec;
    v_ptr := 0;

    while v_ptr /= TEST_SIZE loop
      push_stream(net, MASTER_STREAM, v_vec(v_vec'left downto v_vec'length - g_INPUT_WIDTH));
      v_ptr := v_ptr + G_INPUT_WIDTH;
      v_vec := v_vec(v_vec'left - G_INPUT_WIDTH downto 0) & (G_INPUT_WIDTH - 1 downto 0 => '0');
      wait for 0 ns;
    end loop;

    info("write start");
    wait for SRC_CLK_PERIOD;
    wait;

  end process proc_write;

  proc_read : process is

    variable v_vec : test_vec'subtype;
    variable v_out : std_logic_vector(G_OUTPUT_WIDTH - 1 downto 0);
    variable v_ptr : natural range 0 to TEST_SIZE;

  begin

    rd_complete <= '0';
    wait until not snk_reset;
    v_vec       := test_vec;
    v_ptr       := 0;

    while v_ptr /= TEST_SIZE loop
      pop_stream(net, SLAVE_STREAM, v_out);
      v_ptr := v_ptr + G_OUTPUT_WIDTH;
      check(v_out = v_vec(v_vec'left downto v_vec'length - g_OUTPUT_WIDTH), "data mismatch: "&to_hstring(v_out)&" exp "& to_hstring(v_vec(v_vec'left downto v_vec'length - g_OUTPUT_WIDTH)));
      v_vec := v_vec(v_vec'left - G_OUTPUT_WIDTH downto 0) & (G_OUTPUT_WIDTH - 1 downto 0 => '0');

      if (v_ptr = TEST_SIZE - 1) then
        rd_complete <= '1';
      end if;

      wait for 0 ns;
    end loop;

    info("read complete");
    rd_complete <= '0';
    notify(rd_event);

  end process proc_read;

  main : process is
  begin

    test_runner_setup(runner, runner_cfg);

    test_vec <= v_rv.RandSlv(TEST_SIZE);

    while test_suite loop

      if run("throughput") then
        info("throughput test");
        wait for 3 * SNK_CLK_PERIOD;
        snk_reset <= '0';
        wait until src_valid = '1';
        rd_start  <= '1';
        info("read start");
        wait for SRC_CLK_PERIOD;
        rd_start  <= '0';
        wait until is_active(rd_event);
        test_runner_cleanup(runner);
      end if;

    end loop;

  end process main;

  axi_stream_slave_inst : entity vunit_lib.axi_stream_slave
    generic map (
      SLAVE => slave_axi_stream
    )
    port map (
      aclk     => src_clk,
      areset_n => not snk_reset,
      tvalid   => src_valid,
      tready   => src_ready,
      tdata    => src_data
    );

  axi_stream_master_inst : entity vunit_lib.axi_stream_master
    generic map (
      MASTER => master_axi_stream
    )
    port map (
      aclk     => snk_clk,
      areset_n => not snk_reset,
      tvalid   => snk_valid,
      tready   => snk_ready,
      tdata    => snk_data
    );

  check_stable(src_clk, en, rd_start, rd_complete, src_valid, result("for src_valid."));

  snk_clk <= not snk_clk after SNK_CLK_PERIOD / 2;
  src_clk <= not src_clk after SRC_CLK_PERIOD / 2;
  test_runner_watchdog(runner, 300 us);

end architecture bench;
