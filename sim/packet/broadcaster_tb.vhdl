-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library osvvm;
  use osvvm.randompkg.all;
  use osvvm.coveragepkg.all;

library vunit_lib;
  context vunit_lib.vunit_context;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_clock_generator;
  context bitvis_vip_clock_generator.vvc_context;

library bitvis_vip_axistream;
  context bitvis_vip_axistream.vvc_context;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;

use work.packet_tb_pkg.all;

entity broadcaster_tb is
  generic (
    RUNNER_CFG    : string;
    g_N_PACKETS   : natural := 5;
    g_PACKET_SIZE : natural := 16;
    g_DATA_WIDTH  : natural := 32;
    g_NUM_OUTPUTS : natural := 3
  );
end entity broadcaster_tb;

architecture sim of broadcaster_tb is

  signal          acov      : coverageidtype;
  constant        N_PACKETS : natural := g_N_PACKETS;
  constant        N_BYTES   : natural := g_PACKET_SIZE;
  shared variable v_rv      : randomptype;

begin

  test_harness : entity work.broadcaster_th(sim)
    generic map (
      g_NUM_OUTPUTS => g_NUM_OUTPUTS,
      g_DATA_WIDTH  => g_DATA_WIDTH
    );

  proc_seq : process is

    variable v_pkt_cnt : natural := 0;
    variable v_channel : natural;
    variable v_size    : natural;
    variable v_test    : std_logic_vector(N_BYTES * 8 - 1 downto 0);
    variable v_msg     : t_slv_array(0 to N_BYTES - 1)(7 downto 0);
    variable v_user    : t_user_array(0 to div_ceil(N_BYTES, g_DATA_WIDTH / 8) - 1);

  begin

    ---------------- VUNIT SETUP ---------------
    test_runner_setup(runner, RUNNER_CFG);
    check(g_NUM_OUTPUTS < 4, "Cannot instantiate more than 4 sources");

    info("--- Configuration:" & to_string(N_BYTES) & "B "& to_string(N_PACKETS)&" packets");
    ---------------- OSVVM setup ---------------
    acov <= NewID("ACov");

    ---------------- UVVM SETUP ----------------
    await_uvvm_initialization(VOID);
    disable_log_msg(VVC_BROADCAST, ID_PACKET_DATA);
    log(ID_LOG_HDR, "Configuring VVCs");

    -- Stream Source setup (INPUT)
    log(ID_SEQUENCER, "Configure Encode Source");

    -- Stream Sink setup (OUTPUT)
    log(ID_SEQUENCER, "Configure Decode Sink");

    -- clocks setup
    start_clock(CLOCK_GENERATOR_VVCT, CLK_MAIN, "Starting clock Avalon");

    log(ID_SEQUENCER, "Waiting for release of reset");
    wait for CLK_PERIOD_MAIN;
    log(ID_SEQUENCER, "Waiting for reset propagation");
    wait for CLK_PERIOD_MAIN * 4;

    if run("simple") then
      v_test := v_rv.RandSlv(N_BYTES * 8);
      v_msg  := to_byte_array(v_test);

      axistream_transmit(AXISTREAM_VVCT, AXIS_TX_IDX, v_msg, "Send");

      for i in 0 to g_NUM_OUTPUTS - 1 loop
        axistream_expect(AXISTREAM_VVCT, AXIS_RX_IDX + i, v_msg, "Receiving CH"&to_string(i));
      end loop;

    elsif run("randomize") then
      AddBins(acov, g_N_PACKETS, GenBin(1, g_PACKET_SIZE));

      loop
        v_size := GetRandPoint(acov);
        v_test  := v_rv.RandSlv(N_BYTES * 8);
        v_msg  :=  to_byte_array(v_test);

        axistream_transmit(AXISTREAM_VVCT, AXIS_TX_IDX, v_msg(0 to v_size - 1), "Broadcast bytes: "&to_string(v_size));

        for i in 0 to g_NUM_OUTPUTS - 1 loop
          axistream_expect(AXISTREAM_VVCT, AXIS_RX_IDX + i, v_msg(0 to v_size - 1), "Receiving CH"&to_string(i) & " bytes: "&to_string(v_size));
        end loop;

        ICover(acov,  v_size);
        exit when IsCovered(acov);
      end loop;

      await_completion(VVC_BROADCAST, 10 ms, "Wait for all the VVCs to finish");
      wait for 3 * CLK_PERIOD_MAIN;

      writeBin(acov);
    end if;

    -- UVVM cleanup
    await_completion(VVC_BROADCAST, 10 ms, "Wait for all the VVCs to finish");
    wait for 3 * CLK_PERIOD_MAIN;

    report_alert_counters(FINAL);

    -- VUnit cleanup
    test_runner_cleanup(runner);

  end process proc_seq;

  test_runner_watchdog(runner, 100 ms);

end architecture sim;
