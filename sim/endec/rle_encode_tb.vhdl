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

entity rle_encode_tb is
  generic (
    RUNNER_CFG : string
  );
end entity rle_encode_tb;

architecture bench of rle_encode_tb is

  constant c_TEST_SIZE : positive := 10;

  shared variable v_rv : RandomPType;

  -- Clock period
  constant CLK_PERIOD          : time := 5 ns;
  -- Generics
  constant G_WORD_WIDTH        : positive := 4;
  constant G_COUNT_WIDTH       : positive := 3;
  constant G_WORD_MAX          : positive := 2 ** G_COUNT_WIDTH;
  -- Ports
  signal clk                   : std_logic := '1';
  signal reset                 : std_logic := '1';
  signal flush                 : std_logic := '0';
  signal snk_ready             : std_logic;
  signal snk_valid             : std_logic;
  signal snk_data              : std_logic_vector(G_WORD_WIDTH - 1 downto 0);
  signal src_ready             : std_logic;
  signal src_valid             : std_logic;
  signal src_data              : std_logic_vector(G_WORD_WIDTH + G_COUNT_WIDTH - 1 downto 0);
  -- BFMs
  constant MIN_STALL_CYCLES    : natural        := 1;
  constant MAX_STALL_CYCLES    : natural        := 8;
  constant MASTER_STALL_CONFIG : stall_config_t := new_stall_config(stall_probability => 0.5, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);
  constant SLAVE_STALL_CONFIG  : stall_config_t := new_stall_config(stall_probability => 0.5, MIN_STALL_CYCLES => MIN_STALL_CYCLES, MAX_STALL_CYCLES => MAX_STALL_CYCLES);

  -- streaming write
  constant MASTER_AXI_STREAM : axi_stream_master_t := new_axi_stream_master(
                                                                            data_length => G_WORD_WIDTH,
     STALL_CONFIG                                                                       => MASTER_STALL_CONFIG
   );
  constant MASTER_STREAM     : stream_master_t     := as_stream(MASTER_AXI_STREAM);
  -- streaming read
  constant SLAVE_AXI_STREAM  : axi_stream_slave_t := new_axi_stream_slave(
                                                                          data_length => G_WORD_WIDTH + G_COUNT_WIDTH,
     STALL_CONFIG                                                                     => SLAVE_STALL_CONFIG
   );
  constant SLAVE_STREAM      : stream_slave_t     := as_stream(SLAVE_AXI_STREAM);

  type rec_t is record
    data : std_logic_vector(G_WORD_WIDTH - 1 downto 0);
    cnt  : positive;
  end record rec_t;

  signal rd_event : event_t := new_event("reading complete");

begin

  rle_encode_inst : entity colibri.rle_encode
    generic map (
      g_WORD_WIDTH  => g_WORD_WIDTH,
      g_COUNT_WIDTH => g_COUNT_WIDTH
    )
    port map (
      clk_i       => clk,
      reset_i     => reset,
      flush_i     => flush,
      snk_ready_o => snk_ready,
      snk_valid_i => snk_valid,
      snk_data_i  => snk_data,
      src_ready_i => src_ready,
      src_valid_o => src_valid,
      src_data_o  => src_data
    );

  proc_read : process is

    variable v_act  : actor_t;
    variable msg    : msg_t;
    variable v_rec  : rec_t;
    variable v_data : src_data'subtype;
    variable v_exp  : src_data'subtype;

  begin

    v_act := find("sender");

    for i in 0 to c_TEST_SIZE loop

      if (i = c_TEST_SIZE) then
        flush <= '1';
      end if;

      receive(net, v_act, msg);
      v_rec.data := pop(msg);
      v_rec.cnt  := pop_integer(msg);
      info("Received "&to_hstring(v_rec.data) & " " & to_string(v_rec.cnt));
      pop_stream(net, SLAVE_STREAM, v_data);
      v_exp      := std_logic_vector(to_unsigned(v_rec.cnt, G_COUNT_WIDTH)) & v_rec.data;
      check(v_data = v_exp, "data mismatch");
      info("pop "&to_hstring(v_data));
    end loop;

    notify(rd_event);

  end process proc_read;

  proc_seq : process is

    variable v_old : rec_t;
    variable v_rec : rec_t;
    variable v_act : actor_t := new_actor("sender");
    variable msg   : msg_t;

  begin

    test_runner_setup(runner, runner_cfg);
    wait for CLK_PERIOD;
    reset <= '0';
    wait for CLK_PERIOD;

    if run("coverage") then
      info("coverage");

      for i in 0 to c_TEST_SIZE loop
        v_rec.data := v_rv.RandSlv(G_WORD_WIDTH);

        while v_rec.data = v_old.data loop
          v_rec.data := v_rv.RandSlv(G_WORD_WIDTH);

        end loop;

        v_rec.cnt := v_rv.RandInt(1, G_COUNT_WIDTH - 1);
        info ("Sending "&to_hstring(v_rec.data) & " " & to_string(v_rec.cnt));

        for k in 1 to v_rec.cnt loop
          push_stream(net, MASTER_STREAM, v_rec.data);
        end loop;

        msg   := new_msg;
        push(msg, v_rec.data);
        push_integer(msg, v_rec.cnt);
        send(net, v_act, msg);
        v_old := v_rec;
      end loop;

      wait until is_active(rd_event);
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
