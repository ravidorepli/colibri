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

entity rle_decode_tb is
  generic (
    RUNNER_CFG : string
  );
end entity rle_decode_tb;

architecture bench of rle_decode_tb is

  constant c_TEST_SIZE : positive := 10;

  shared variable v_rv         : randomptype;
  -- Clock period
  constant CLK_PERIOD          : time := 5 ns;
  -- Generics
  constant G_WORD_WIDTH        : positive := 4;
  constant G_COUNT_WIDTH       : positive := 3;
  -- Ports
  signal clk                   : std_logic := '1';
  signal reset                 : std_logic := '1';
  signal flush                 : std_logic := '0';
  signal snk_ready             : std_logic;
  signal snk_valid             : std_logic;
  signal snk_data              : std_logic_vector(G_WORD_WIDTH + G_COUNT_WIDTH - 1 downto 0);
  signal src_ready             : std_logic;
  signal src_valid             : std_logic;
  signal src_data              : std_logic_vector(G_WORD_WIDTH  - 1 downto 0);
  -- BFMs
  constant MIN_STALL_CYCLES    : natural        := 1;
  constant MAX_STALL_CYCLES    : natural        := 8;
  constant MASTER_STALL_CONFIG : stall_config_t := new_stall_config(stall_probability => 0.5, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);
  constant SLAVE_STALL_CONFIG  : stall_config_t := new_stall_config(stall_probability => 0.5, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);

  -- streaming write
  constant MASTER_AXI_STREAM : axi_stream_master_t := new_axi_stream_master(
                                                                            data_length => G_WORD_WIDTH + G_COUNT_WIDTH,
     STALL_CONFIG                                                                       => MASTER_STALL_CONFIG
   );
  constant MASTER_STREAM     : stream_master_t     := as_stream(MASTER_AXI_STREAM);
  -- streaming read
  constant SLAVE_AXI_STREAM  : axi_stream_slave_t := new_axi_stream_slave(
                                                                          data_length => G_WORD_WIDTH,
     STALL_CONFIG                                                                     => SLAVE_STALL_CONFIG
   );
  constant SLAVE_STREAM      : stream_slave_t     := as_stream(SLAVE_AXI_STREAM);

begin

  rle_decode_inst : entity colibri.rle_decode
    generic map (
      g_WORD_WIDTH  => g_WORD_WIDTH,
      g_COUNT_WIDTH => g_COUNT_WIDTH
    )
    port map (
      clk_i       => clk,
      reset_i     => reset,
      snk_ready_o => snk_ready,
      snk_valid_i => snk_valid,
      snk_data_i  => snk_data,
      src_ready_i => src_ready,
      src_valid_o => src_valid,
      src_data_o  => src_data
    );

  proc_seq : process is

    variable v_data  : snk_data'subtype;
    variable v_recv  : src_data'subtype;
    variable v_count : positive;

  begin

    test_runner_setup(runner, RUNNER_CFG);
    info("Starting OSVVM");

    wait for CLK_PERIOD;
    reset <= '0';
    wait for CLK_PERIOD;

    if run("coverage") then

      for i in 0 to c_TEST_SIZE loop
        v_data  := v_rv.RandSlv(16, 127, G_COUNT_WIDTH + G_WORD_WIDTH);
        wait for 1 ns;
        push_stream(net, MASTER_STREAM, v_data);
        v_count := to_integer(unsigned(v_data(v_data'left downto G_WORD_WIDTH)));

        for k in 1 to v_count loop
          pop_stream(net, SLAVE_STREAM, v_recv);
          -- info(to_hstring(v_recv) & " " & to_hstring(v_data));
          check(v_recv = v_data(g_WORD_WIDTH - 1 downto 0), "data mismatch ");
        end loop;

      end loop;

      test_runner_cleanup(runner);
    end if;

  end process proc_seq;

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

  test_runner_watchdog(runner, 100 us);

end architecture bench;
