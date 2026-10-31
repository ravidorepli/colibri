-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.com_context;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_clock_generator;
  context bitvis_vip_clock_generator.vvc_context;

library bitvis_vip_avalon_st;
  context bitvis_vip_avalon_st.vvc_context;

library bitvis_vip_axistream;
  context bitvis_vip_axistream.vvc_context;

library colibri;
  context colibri.common;

library osvvm;
  use osvvm.randompkg.all;
  use osvvm.coveragepkg.all;

use work.cc_misc_tb_pkg.all;

entity packet_cc_ram_fifo_tb is
  generic (

    RUNNER_CFG       : string;
    g_SNK_DATA_WIDTH : natural := 16;
    g_SRC_DATA_WIDTH : natural := 32
  );
end entity packet_cc_ram_fifo_tb;

architecture sim of packet_cc_ram_fifo_tb is

  constant c_N_PACKETS : natural                                  := 31;
  constant c_MIN_SIZE  : natural                                  := 2;
  constant c_MAX_MSG   :
   t_slv_array(c_MIN_SIZE + c_N_PACKETS - 1 downto 0)(7 downto 0) := fill_array(c_MIN_SIZE + c_N_PACKETS);
  constant c_HUGE_MSG   :
   t_slv_array(512 -1 downto 0)(7 downto 0) := fill_array(512);
begin

  test_harness : entity work.packet_cc_ram_fifo_th(sim)
    generic map (
      g_SNK_DATA_WIDTH => g_SNK_DATA_WIDTH,
      g_SRC_DATA_WIDTH => g_SRC_DATA_WIDTH
    );

  proc_sequencer : process is

    variable v_act : actor_t;
    variable msg   : msg_t;

  begin

    ---------------- VUNIT SETUP ---------------
    test_runner_setup(runner, RUNNER_CFG);

    ---------------- UVVM SETUP ----------------
    await_uvvm_initialization(VOID);
    disable_log_msg(VVC_BROADCAST, ID_PACKET_DATA);
    log(ID_LOG_HDR, "Configuring VVCs");

    -- Stream Source setup (INPUT)
    log(ID_SEQUENCER, "Configure Source");

    -- Stream Sink setup (OUTPUT)
    log(ID_SEQUENCER, "Configure Sink");

    -- clocks setup
    start_clock(CLOCK_GENERATOR_VVCT, c_CLK_40, "Starting clock 40 MHz");
    start_clock(CLOCK_GENERATOR_VVCT, c_CLK_60, "Starting clock 60 MHz");

    log(ID_SEQUENCER, "Waiting for release of reset");
    wait for c_CLK_PERIOD_40;
    log(ID_SEQUENCER, "Waiting for reset propagation");
    wait for c_CLK_PERIOD_40 * 10;
    -- TEST : Encode Decode behaviour
    if run("coverage") then
      log(ID_SEQUENCER, "Sending " & to_string(c_N_PACKETS) & " packets");

      for i in 0 to c_N_PACKETS loop
        avalon_st_transmit(AVALON_ST_VVCT, c_AV_ST_SRC_IDX,
                           c_MAX_MSG(c_MAX_MSG'length - 1 downto i),
                           "Transmitting msg "&to_string(c_MAX_MSG'length - i));
        axistream_expect(AXISTREAM_VVCT, c_AXIS_SIDE_IDX,
                         to_byte_array(std_logic_vector(unsigned(to_unsigned(c_MAX_MSG'length - i, 8)))),
                         "expecting size "&to_string(c_MAX_MSG'length - i));
      end loop;

      wait for 150 * c_CLK_PERIOD_40;

      log(ID_SEQUENCER, "Add expected fixed size " & to_string(c_N_PACKETS) & " packets to Recv Queue");

      for i in 0 to c_N_PACKETS loop
        avalon_st_expect(AVALON_ST_VVCT, c_AV_ST_SNK_IDX,
                         c_MAX_MSG(c_MAX_MSG'length - 1 downto i),
                         "Receiving packet #"&to_string(i)&" size "&to_string(c_MAX_MSG'length - i));
      end loop;

    elsif run("drop") then
      log(ID_SEQUENCER, "drop packets");

      for i in 0 to c_N_PACKETS loop

        if (i mod 2 = 0) then
          avalon_st_transmit(AVALON_ST_VVCT, c_AV_ST_SRC_IDX,
                             c_MAX_MSG(c_MAX_MSG'length - 1 downto i),
                             "Transmitting msg "&to_string(c_MAX_MSG'length - i));
          axistream_expect(AXISTREAM_VVCT, c_AXIS_SIDE_IDX,
                           to_byte_array(std_logic_vector(unsigned(to_unsigned(c_MAX_MSG'length - i, 8)))),
                           "expecting size "&to_string(c_MAX_MSG'length - i));
        else
          avalon_st_transmit(AVALON_ST_VVCT, c_AV_ST_SRC_IDX,"1",
                             c_MAX_MSG(c_MAX_MSG'length - 1 downto i),
                             "Drop MSG",C_SCOPE);
        end if;
      end loop;

      wait for 150 * c_CLK_PERIOD_40;

      log(ID_SEQUENCER, "Add expected fixed size " & to_string(c_N_PACKETS) & " packets to Recv Queue");

      for i in 0 to c_N_PACKETS loop
        if (i mod 2 = 0) then
          avalon_st_expect(AVALON_ST_VVCT, c_AV_ST_SNK_IDX,
                           c_MAX_MSG(c_MAX_MSG'length - 1 downto i),
                           "Receiving "&to_string(c_MAX_MSG'length - i));
        end if;
      end loop;
    elsif run("too_big") then
          avalon_st_transmit(AVALON_ST_VVCT, c_AV_ST_SRC_IDX,
                             c_HUGE_MSG,
                             "Transmitting HUGE "&to_string(c_HUGE_MSG'length ));
          await_completion(AVALON_ST_VVCT, c_AV_ST_SRC_IDX, 10 us);
          avalon_st_transmit(AVALON_ST_VVCT, c_AV_ST_SRC_IDX,
                             c_MAX_MSG,
                             "Transmitting msg "&to_string(c_MAX_MSG'length));
          axistream_expect(AXISTREAM_VVCT, c_AXIS_SIDE_IDX,
                           to_byte_array(std_logic_vector(unsigned(to_unsigned(c_MAX_MSG'length , 8)))),
                           "expecting size "&to_string(c_MAX_MSG'length));
          avalon_st_expect(AVALON_ST_VVCT, c_AV_ST_SNK_IDX,
                           c_MAX_MSG,
                           "Receiving "&to_string(c_MAX_MSG'length));
    end if;

    -- UVVM cleanup
    await_completion(AVALON_ST_VVCT, c_AV_ST_SRC_IDX, 10 us);
    await_completion(AVALON_ST_VVCT, c_AV_ST_SNK_IDX, 10 us);

    avalon_st_receive(AVALON_ST_VVCT, c_AV_ST_SNK_IDX, c_MAX_MSG'length, c_MAX_MSG(0)'length, "Receiving");
    wait for 10 * c_CLK_PERIOD_40;
    -- report UVVM
    report_alert_counters(FINAL);

    v_act := find("print_coverage");
    msg   := new_msg;
    push_integer(msg, 0);
    send(net, v_act, msg);
    -- VUnit cleanup
    test_runner_cleanup(runner);

  end process proc_sequencer;

  test_runner_watchdog(runner, 100 us);

end architecture sim;
