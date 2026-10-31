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

library colibri;
  context colibri.common;
use work.misc_tb_pkg.all;

entity be_remove_lead_tb is
  generic (

    RUNNER_CFG : string
  );
end entity be_remove_lead_tb;

architecture sim of be_remove_lead_tb is

  constant c_N_PACKETS : natural                                                    := 20;
  constant c_MIN_SIZE  : natural                                                    := 10;
  constant c_MAX_MSG   :
  t_slv_array(c_MIN_SIZE + c_N_PACKETS - 1 downto 0)(7 downto 0)                    := fill_array(c_MIN_SIZE + c_N_PACKETS);
  constant c_MSG_HEAD  : t_slv_array(c_MAX_MSG'length + c_HEADER_SIZE - 1 downto 0) := add_header(c_MAX_MSG);

begin

  test_harness : entity work.be_remove_lead_th(sim);

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

    -- clocks setup
    start_clock(CLOCK_GENERATOR_VVCT, c_CLK_40, "Starting clock 40 MHz");

    log(ID_SEQUENCER, "Waiting for release of reset");
    wait for c_CLK_PERIOD_40;
    log(ID_SEQUENCER, "Waiting for reset propagation");
    wait for c_CLK_PERIOD_40 * 4;
    -- TEST : Encode Decode behaviour
    if run("remove_lead") then
      log(ID_SEQUENCER, "Add expected fixed size " & to_string(c_N_PACKETS) & " packets to Recv Queue");

      log(ID_SEQUENCER, "Sending " & to_string(c_N_PACKETS) & " packets");

      for i in 0 to c_N_PACKETS loop
        avalon_st_transmit(AVALON_ST_VVCT, c_AV_ST_SRC_IDX,
                           c_MSG_HEAD(c_MSG_HEAD'length - 1 downto i),
                           "Transmitting msg "&to_string(c_MAX_MSG'length - i));

      end loop;

      for i in 0 to c_N_PACKETS loop
        avalon_st_expect(AVALON_ST_VVCT, c_AV_ST_SNK_IDX,
                         c_MAX_MSG(c_MAX_MSG'length - 1 downto i),
                         "Receiving "&to_string(c_MAX_MSG'length - i));
        await_completion(AVALON_ST_VVCT, c_AV_ST_SNK_IDX, 10 us);
        wait for c_CLK_PERIOD_40 * 10;
      end loop;

    end if;

    -- UVVM cleanup
    await_completion(AVALON_ST_VVCT, c_AV_ST_SRC_IDX, 10 us);
    await_completion(AVALON_ST_VVCT, c_AV_ST_SNK_IDX, 10 us);
    report_alert_counters(FINAL);

    -- VUnit cleanup
    test_runner_cleanup(runner);

  end process proc_sequencer;

end architecture sim;
