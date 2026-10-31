-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library vunit_lib;
  context vunit_lib.vunit_context;

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

use work.stream_iface_tb_pkg.all;

entity axis_to_avst_tb is
  generic (
    RUNNER_CFG : string;

    --! Avalon-Stream byte order. (AXI-Stream is LITTLE by spec.)
    g_AVST_ENDIANNESS : endian_t := BIG
  );
end entity axis_to_avst_tb;

architecture sim of axis_to_avst_tb is

  constant c_N_PACKETS : natural                                  := 20;
  constant c_MIN_SIZE  : natural                                  := 10;
  constant c_MSG       :
   t_slv_array(c_MIN_SIZE + c_N_PACKETS - 1 downto 0)(7 downto 0) := fill_array(c_MIN_SIZE + c_N_PACKETS);

begin

  test_harness : entity work.axis_to_avst_th(sim)
    generic map (
      g_AVST_ENDIANNESS => g_AVST_ENDIANNESS
    );

  proc_sequencer : process is
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
    shared_avalon_st_vvc_config(c_AV_ST_SNK_IDX).bfm_config.first_symbol_in_msb := (g_AVST_ENDIANNESS = BIG);

    -- clocks setup
    start_clock(CLOCK_GENERATOR_VVCT, c_CLK_40, "Starting clock 40 MHz");

    log(ID_SEQUENCER, "Waiting for release of reset");
    wait for c_CLK_PERIOD_40;
    log(ID_SEQUENCER, "Waiting for reset propagation");
    wait for c_CLK_PERIOD_40 * 4;
    -- TEST : Encode Decode behaviour
    if run("axis_to_avst") then
      log(ID_SEQUENCER, "Add expected fixed size " & to_string(c_N_PACKETS) & " packets to Recv Queue");

      for i in 0 to c_N_PACKETS loop
        avalon_st_expect(AVALON_ST_VVCT, c_AV_ST_SNK_IDX,
                         c_MSG(c_MSG'length - 1 downto i),
                         "Receiving "&to_string(c_MSG'length - i));
      end loop;

      log(ID_SEQUENCER, "Sending " & to_string(c_N_PACKETS) & " packets");

      for i in 0 to c_N_PACKETS loop
        axistream_transmit(AXISTREAM_VVCT, c_AXIS_SRC_IDX,
                           c_MSG(c_MSG'length - 1 downto i),
                           "Transmitting msg "&to_string(c_MSG'length - i));
      end loop;

    end if;

    -- UVVM cleanup
    await_completion(AXISTREAM_VVCT, c_AXIS_SRC_IDX, 10 us);
    await_completion(AVALON_ST_VVCT, c_AV_ST_SNK_IDX, 10 us);
    report_alert_counters(FINAL);

    -- VUnit cleanup
    test_runner_cleanup(runner);

  end process proc_sequencer;

end architecture sim;
