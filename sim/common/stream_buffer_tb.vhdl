-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

--! @file stream_buffer_tb.vhdl
--! @brief Simple generic stream buffer Testbench
--! @author Alberto Perro
--! @date 30-04-2026 Created
--! @version 0.1
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;

library osvvm;
  context osvvm.osvvmcontext;

library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;

--==================================================================================================
--! @brief Simple generic stream buffer Testbench
--! @details

-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity stream_buffer_tb is
  generic (
    RUNNER_CFG          : string;
    g_REGISTER_DATAPATH : boolean := false
  );
end entity stream_buffer_tb;

architecture sim of stream_buffer_tb is

  constant c_TEST_SIZE : positive := 100;

  --! GENERICS (as constants)

  constant c_DATA_WIDTH : natural := 8;

  signal reset : std_logic := '1';
  signal clk   : std_logic := '1';

  --! ports signals
  signal snk_data  : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal snk_valid : std_logic;
  signal snk_ready : std_logic;
  signal src_data  : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal src_ready : std_logic;
  signal src_valid : std_logic;

  -- BFMs
  shared variable v_rv : randomptype;

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

  proc_main_tb : process is

    variable v_data  : snk_data'subtype;
    variable v_recv  : src_data'subtype;
    variable v_count : positive;

  begin

    test_runner_setup(runner, RUNNER_CFG);
    info("Starting OSVVM");
    info("Waiting for reset release...");
    osvvm.TbUtilPkg.WaitForLevel(reset, '0');
    info("Test Started");

    for i in 0 to c_TEST_SIZE loop
      v_data := v_rv.RandSlv(16, 127, c_DATA_WIDTH);
      wait for 1 ns;
      push_stream(net, MASTER_STREAM, v_data);
      pop_stream(net, SLAVE_STREAM, v_recv);
      check(v_recv = v_data, "data mismatch "&to_hstring(v_recv) & " " & to_hstring(v_data));

    end loop;

    osvvm.TbUtilPkg.WaitForClock(clk, 100);
    info("Test Finished");
    test_runner_cleanup(runner);

  end process proc_main_tb;

  test_runner_watchdog(runner, 100 us);

  osvvm.TbUtilPkg.CreateClock(clk, 10 ns);
  osvvm.TbUtilPkg.CreateReset(reset, '1', clk, 50 ns, 0 ns);

  dut : entity colibri.stream_buffer
    generic map (
      g_DATA_WIDTH        => c_DATA_WIDTH,
      g_REGISTER_DATAPATH => g_REGISTER_DATAPATH
    )
    port map (
      reset_i     => reset,
      clk_i       => clk,
      snk_data_i  => snk_data,
      snk_valid_i => snk_valid,
      snk_ready_o => snk_ready,
      src_data_o  => src_data,
      src_ready_i => src_ready,
      src_valid_o => src_valid
    );

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

end architecture sim;
