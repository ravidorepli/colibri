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
  use colibri.utils.all;
  use colibri.aurora_const.all;
use work.aurora_loopback_pkg.all;

entity aurora_lane_mismatch_tb is
  generic (
    RUNNER_CFG     : string;
    g_LANE_WIDTH   : natural := 32
  );
end entity aurora_lane_mismatch_tb;

architecture sim of aurora_lane_mismatch_tb is

  constant N_PACKETS : natural                                                    := 20;
  constant MIN_SIZE  : natural                                                    := 10;
  constant MAX_MSG   : t_slv_array(MIN_SIZE + N_PACKETS - 1 downto 0)(7 downto 0) := fill_array(MIN_SIZE + N_PACKETS);
  signal rx_error : std_logic := '0';
  
begin

  test_harness : entity work.aurora_lane_mismatch_th(sim)
    generic map (
      g_LANE_WIDTH   => g_LANE_WIDTH
    );

  rx_error <= << signal test_harness.rx_error : std_logic >>;

  sequencer_proc : process is
  begin

    ---------------- VUNIT SETUP ---------------
    test_runner_setup(runner, RUNNER_CFG);

    ---------------- UVVM SETUP ----------------
    await_uvvm_initialization(VOID);
    disable_log_msg(VVC_BROADCAST, ID_PACKET_DATA);
    log(ID_LOG_HDR, "Configuring VVCs");

    -- Stream Source setup (INPUT)
    log(ID_SEQUENCER, "Configure Encode Source");

    -- Stream Sink setup (OUTPUT)
    log(ID_SEQUENCER, "Configure Decode Sink");

    -- clocks setup
    start_clock(CLOCK_GENERATOR_VVCT, CLK_ELINK, "Starting clock Elink");
    start_clock(CLOCK_GENERATOR_VVCT, CLK_AVALON, "Starting clock Avalon");

    log(ID_SEQUENCER, "Waiting for release of reset");
    wait for CLK_PERIOD_AVALON;
    log(ID_SEQUENCER, "Waiting for reset propagation");
    wait for CLK_PERIOD_AVALON * 4;
    log(ID_SEQUENCER, "Waiting for link initialization");
    -- TEST : Encode Decode behaviour
    if run("lane_mismatch_4_to_1") then
      await_value(rx_error, '1', CLK_PERIOD_AVALON, 100 us, "Waiting for receiver to toggle error");
    end if;

    -- UVVM cleanup
    await_completion(VVC_BROADCAST, 10 ms, "Wait for all the VVCs to finish");
    wait for 100 us;

    -- await_completion(AVALON_ST_VVCT, AURORA_TX_IDX, 100 us);
    -- await_completion(AVALON_ST_VVCT, AURORA_RX_IDX, 100 us);
    report_alert_counters(FINAL);

    -- VUnit cleanup
    test_runner_cleanup(runner);

  end process sequencer_proc;

end architecture sim;
