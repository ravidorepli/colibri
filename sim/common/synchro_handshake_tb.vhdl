-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;

library osvvm;
  use osvvm.randompkg.all;

--
library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;

--==================================================================================================
--! @brief Clock Domain Boundary Synchronizer with Handshake Test Bench
--! @details
--!
--! This testbench uses two stream VVCs with stall probabilities of 50% (valid, ready).
--! A set of c_TEST_SIZE randomly generated data is sent from sink to source.
--! VVCs check that the transmitted data matches the received data.
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity synchro_handshake_tb is
  generic (
    RUNNER_CFG : string
  );
end entity synchro_handshake_tb;

architecture bench of synchro_handshake_tb is

  constant c_TEST_SIZE : positive := 10;

  shared variable v_rv         : randomptype;
  -- Clock period
  constant c_CLK_PERIOD_A      : time := 5 ns;
  constant c_CLK_PERIOD_B      : time := 17 ns;
  -- Generics
  constant c_DATA_WIDTH        : positive := 4;
  -- Ports
  signal src_clk               : std_logic := '1';
  signal snk_clk               : std_logic := '1';
  signal reset                 : std_logic := '1';
  signal snk_ready             : std_logic;
  signal snk_valid             : std_logic;
  signal snk_data              : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal src_ready             : std_logic;
  signal src_valid             : std_logic;
  signal src_data              : std_logic_vector(c_DATA_WIDTH  - 1 downto 0);
  -- BFMs
  constant MIN_STALL_CYCLES    : natural        := 1;
  constant MAX_STALL_CYCLES    : natural        := 8;
  constant MASTER_STALL_CONFIG : stall_config_t := new_stall_config(stall_probability => 0.5, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);
  constant SLAVE_STALL_CONFIG  : stall_config_t := new_stall_config(stall_probability => 0.5, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);

  -- streaming write
  constant MASTER_AXI_STREAM : axi_stream_master_t := new_axi_stream_master(
                                                                            data_length => c_DATA_WIDTH,
     STALL_CONFIG                                                                       => MASTER_STALL_CONFIG
   );
  constant MASTER_STREAM     : stream_master_t     := as_stream(MASTER_AXI_STREAM);
  -- streaming read
  constant SLAVE_AXI_STREAM  : axi_stream_slave_t := new_axi_stream_slave(
                                                                          data_length => c_DATA_WIDTH,
     STALL_CONFIG                                                                     => SLAVE_STALL_CONFIG
   );
  constant SLAVE_STREAM      : stream_slave_t     := as_stream(SLAVE_AXI_STREAM);

begin

  proc_seq : process is

    variable v_data  : snk_data'subtype;
    variable v_recv  : src_data'subtype;
    variable v_count : positive;

  begin

    test_runner_setup(runner, RUNNER_CFG);
    info("Starting OSVVM");

    wait for c_CLK_PERIOD_B * 3;
    reset <= '0';
    wait for c_CLK_PERIOD_B;

    if run("coverage") then

      for i in 0 to c_TEST_SIZE loop
        v_data := v_rv.RandSlv(16, 127, c_DATA_WIDTH);
        wait for 1 ns;
        push_stream(net, MASTER_STREAM, v_data);
        pop_stream(net, SLAVE_STREAM, v_recv);
        check(v_recv = v_data, "data mismatch "&to_hstring(v_recv) & " " & to_hstring(v_data));

      end loop;

      test_runner_cleanup(runner);
    end if;

  end process proc_seq;

  snk_clk <= not snk_clk after c_CLK_PERIOD_A / 2;
  src_clk <= not src_clk after c_CLK_PERIOD_B / 2;

  axi_stream_slave_inst : entity vunit_lib.axi_stream_slave
    generic map (
      SLAVE => slave_axi_stream
    )
    port map (
      aclk     => src_clk,
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
      aclk     => snk_clk,
      areset_n => not reset,
      tvalid   => snk_valid,
      tready   => snk_ready,
      tdata    => snk_data
    );

  synchro_handshake_inst : entity colibri.synchro_handshake
    generic map (
      g_DATA_WIDTH => c_DATA_WIDTH
    )
    port map (
      snk_clk_i   => snk_clk,
      src_clk_i   => src_clk,
      reset_i     => reset,
      snk_data_i  => snk_data,
      snk_valid_i => snk_valid,
      snk_ready_o => snk_ready,
      src_data_o  => src_data,
      src_valid_o => src_valid,
      src_ready_i => src_ready
    );

  test_runner_watchdog(runner, 100 us);

end architecture bench;
