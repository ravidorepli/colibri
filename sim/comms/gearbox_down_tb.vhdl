-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;

library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;

entity gearbox_down_tb is
  generic (
    RUNNER_CFG : string
  );
end entity gearbox_down_tb;

architecture bench of gearbox_down_tb is

  -- Clock period
  constant CLK_PERIOD    : time := 5 ns;
  -- Generics
  constant g_INPUT_WIDTH : integer := 12;
  constant g_OUTPUT_WIDTH : integer := 4;
  -- Ports
  signal clk             : std_logic := '1';
  signal reset           : std_logic := '1';
  signal snk_data        : std_logic_vector(g_INPUT_WIDTH - 1 downto 0);
  signal snk_valid       : std_logic;
  signal snk_ready       : std_logic;
  signal src_data        : std_logic_vector(g_OUTPUT_WIDTH - 1 downto 0);
  signal src_valid       : std_logic;
  signal src_ready       : std_logic;

  -- BFMs
  constant MIN_STALL_CYCLES    : natural        := 1;
  constant MAX_STALL_CYCLES    : natural        := 8;
  constant MASTER_STALL_CONFIG : stall_config_t := new_stall_config(stall_probability => 0.9, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);
  constant SLAVE_STALL_CONFIG  : stall_config_t := new_stall_config(stall_probability => 0.01, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);

  -- streaming write
  constant MASTER_AXI_STREAM : axi_stream_master_t := new_axi_stream_master(
                                                                            data_length => 12,
     STALL_CONFIG                                                                       => MASTER_STALL_CONFIG
   );
  constant MASTER_STREAM     : stream_master_t     := as_stream(MASTER_AXI_STREAM);
  -- streaming read
  constant SLAVE_AXI_STREAM  : axi_stream_slave_t := new_axi_stream_slave(
                                                                          data_length => 4,
     STALL_CONFIG                                                                     => SLAVE_STALL_CONFIG
   );
  constant SLAVE_STREAM      : stream_slave_t     := as_stream(SLAVE_AXI_STREAM);

begin

  gearbox_down_inst : entity colibri.gearbox
    generic map (
      g_INPUT_WIDTH => g_INPUT_WIDTH,
      g_OUTPUT_WIDTH => g_OUTPUT_WIDTH
    )
    port map (
      clk_i       => clk,
      reset_i     => reset,
      snk_data_i  => snk_data,
      snk_valid_i => snk_valid,
      snk_ready_o => snk_ready,
      src_data_o  => src_data,
      src_valid_o => src_valid,
      src_ready_i => src_ready
    );

  main : process is

    variable v_data    : std_logic_vector(g_OUTPUT_WIDTH - 1 downto 0);
    variable v_data_tx : std_logic_vector(g_INPUT_WIDTH - 1 downto 0);

  begin

    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      if run("test_alive") then
        info("Hello world test_alive");
        wait for CLK_PERIOD;
        reset <= '0';
        wait for 3 * CLK_PERIOD;

        for i in 0 to 3 loop
          v_data_tx := std_logic_vector(to_unsigned(i * 3, 4) & to_unsigned(i * 3 + 1, 4) & to_unsigned(i * 3 + 2, 4));
          push_stream(net, MASTER_STREAM, v_data_tx);
        end loop;

        for i in 0 to 11 loop
          pop_stream(net, SLAVE_STREAM, v_data);
          check(v_data = std_logic_vector(to_unsigned(i,4)), "data mismatch "&to_hstring(v_data)&"=/="&to_hstring(to_unsigned(i,4)));
        end loop;

        wait for 100 * CLK_PERIOD;
        test_runner_cleanup(runner);
      end if;

    end loop;

  end process main;

  clk <= not clk after CLK_PERIOD / 2;

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
