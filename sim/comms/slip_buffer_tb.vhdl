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

entity slip_buffer_tb is
  generic (
    RUNNER_CFG : string
  );
end entity slip_buffer_tb;

architecture sim of slip_buffer_tb is

  -- OSSVM vars
  shared variable v_rv : RandomPType;

  -- Clock period
  constant CLK_PERIOD          : time := 5 ns;
  -- Generics
  constant G_DATA_WIDTH        : positive := 8;
  -- Ports
  signal clk                   : std_logic := '1';
  signal reset                 : std_logic := '1';
  signal slip                  : std_logic;
  signal snk_data              : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
  signal snk_valid             : std_logic;
  signal snk_ready             : std_logic;
  signal src_valid             : std_logic;
  signal src_ready             : std_logic;
  signal src_data              : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
  -- BFMs
  constant MIN_STALL_CYCLES    : natural        := 1;
  constant MAX_STALL_CYCLES    : natural        := 8;
  constant MASTER_STALL_CONFIG : stall_config_t := new_stall_config(stall_probability => 0.5, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);
  constant SLAVE_STALL_CONFIG  : stall_config_t := new_stall_config(stall_probability => 0.5, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);

  -- streaming write
  constant MASTER_AXI_STREAM : axi_stream_master_t := new_axi_stream_master(
                                                                            data_length => G_DATA_WIDTH,
     STALL_CONFIG                                                                       => MASTER_STALL_CONFIG
   );
  constant MASTER_STREAM     : stream_master_t     := as_stream(MASTER_AXI_STREAM);
  -- streaming read
  constant SLAVE_AXI_STREAM  : axi_stream_slave_t := new_axi_stream_slave(
                                                                          data_length => G_DATA_WIDTH,
     STALL_CONFIG                                                                     => SLAVE_STALL_CONFIG
   );
  constant SLAVE_STREAM      : stream_slave_t     := as_stream(SLAVE_AXI_STREAM);

  constant TEST_SIZE   : natural := 100 * G_DATA_WIDTH;
  signal   test_vec    : std_logic_vector(TEST_SIZE - 1 downto 0);
  signal   slip_enable : event_t := new_event("enable slip");
  signal   wr_start    : event_t := new_event("writing start");
  signal   rd_event    : event_t := new_event("reading complete");
  signal   slip_cnt    : natural := 0;
  signal   s_data_exp  : src_data'subtype;

begin

  slip_buffer_inst : entity colibri.slip_buffer
    generic map (
      g_DATA_WIDTH => g_DATA_WIDTH
    )
    port map (
      clk_i       => clk,
      reset_i     => reset,
      slip_i      => slip,
      snk_data_i  => snk_data,
      snk_valid_i => snk_valid,
      snk_ready_o => snk_ready,
      src_valid_o => src_valid,
      src_ready_i => src_ready,
      src_data_o  => src_data
    );

  proc_write : process is

    variable v_vec : test_vec'subtype;
    variable v_ptr : natural;

  begin

    wait until not reset;
    wait until is_active(wr_start);
    v_vec := test_vec;
    v_ptr := 0;

    while v_ptr /= TEST_SIZE loop
      push_stream(net, MASTER_STREAM, v_vec(v_vec'left downto v_vec'length - g_DATA_WIDTH));
      v_ptr := v_ptr + G_DATA_WIDTH;
      v_vec := v_vec(v_vec'left - G_DATA_WIDTH downto 0) & (G_DATA_WIDTH - 1 downto 0 => '0');
      wait for 0 ns;
    end loop;

    info("write complete");

  end process proc_write;

  proc_read : process is
    variable v_out : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
  begin
    wait until not reset;
    while true loop
    pop_stream(net, SLAVE_STREAM, v_out);
    wait for 0 ns;
    end loop;
  end process proc_read;

  proc_check : process is

    variable v_vec : std_logic_vector(TEST_SIZE + G_DATA_WIDTH - 1 downto 0);
    variable v_exp : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    variable v_ptr : natural range 0 to TEST_SIZE;

  begin

    wait until not reset;
    v_vec := (G_DATA_WIDTH - 1 downto 0 => '0') & test_vec;
    v_ptr := 0;

    while v_ptr < TEST_SIZE - G_DATA_WIDTH loop
      if(src_ready and src_valid) then
      v_ptr      := v_ptr + G_DATA_WIDTH;
      v_exp      := v_vec(v_vec'left - v_ptr + slip_cnt downto v_vec'length - G_DATA_WIDTH - v_ptr + slip_cnt);
      s_data_exp <= v_exp;
      check(src_data = v_exp, "data mismatch: "&to_hstring(src_data)&" exp "& to_hstring(v_exp));
      end if;

      wait for CLK_PERIOD;
    end loop;

    wait for 10 ns;
    info("read complete");
    notify(rd_event);

  end process proc_check;

  proc_slip : process is

    variable v_slip : std_logic;

  begin

    wait until is_active(slip_enable);

    while true loop
      v_slip := v_rv.RandSlv(1)(1) and not reset;
      slip   <= v_slip;
      wait for CLK_PERIOD;

      if (v_slip) then
        if (slip_cnt = G_DATA_WIDTH - 1) then
          slip_cnt <= 0;
        else
          slip_cnt <= slip_cnt + 1;
        end if;
      end if;

    end loop;

  end process proc_slip;

  main : process is

    variable v_data : snk_data'subtype;

  begin

    test_runner_setup(runner, runner_cfg);
    test_vec <= v_rv.RandSlv(TEST_SIZE);

    while test_suite loop
      wait for CLK_PERIOD;
      reset <= '0';

      if run("passthrough") then
        info("passthrough");
        wait for CLK_PERIOD;
        notify(wr_start);
        wait until is_active(rd_event);
      elsif run("slip")  then
        info("test slip");
        wait for CLK_PERIOD;
        notify(slip_enable);
        notify(wr_start);
        wait until is_active(rd_event);
      end if;

      test_runner_cleanup(runner);
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

end architecture sim;
