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

entity aurora_loopback_tb is
  generic (
    RUNNER_CFG     : string;
    g_ERROR_INJECT : boolean := false;
    g_DELAY_LANE   : boolean := false;
    g_NUM_LANES    : natural := 8;
    g_LANE_WIDTH   : natural := 4
  );
end entity aurora_loopback_tb;

architecture sim of aurora_loopback_tb is

  constant N_PACKETS : natural                                                    := 20;
  constant MIN_SIZE  : natural                                                    := 10;
  constant MAX_MSG   : t_slv_array(MIN_SIZE + N_PACKETS - 1 downto 0)(7 downto 0) := fill_array(MIN_SIZE + N_PACKETS);

begin

  test_harness : entity work.aurora_loopback_th(sim)
    generic map (
      g_DELAY_LANE   => g_DELAY_LANE,
      g_ERROR_INJECT => g_ERROR_INJECT,
      g_NUM_LANES    => g_NUM_LANES,
      g_LANE_WIDTH   => g_LANE_WIDTH
    );

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
    wait for 100 us;
    -- TEST : Encode Decode behaviour
    if run("loopback_encode_decode") then
      log(ID_SEQUENCER, "Sending packet to sync with Decoder FSM"); -- this is needed because consumer MUST be ready to enable sync
      avalon_st_transmit(AVALON_ST_VVCT, AURORA_TX_IDX, MAX_MSG(MAX_MSG'length - 1 downto 0), "Transmitting msg for synchronization "&to_string(MAX_MSG'length - 0));

      for i in 0 to 2 loop
        if (g_ERROR_INJECT) then
          avalon_st_transmit(AVALON_ST_VVCT, AURORA_TX_IDX, MAX_MSG(MAX_MSG'length - 1 downto 0), "Transmitting msg for synchronization "&to_string(MAX_MSG'length - 0));
        end if;
        log(ID_SEQUENCER, "Sending " & to_string(N_PACKETS) & " packets");

        log(ID_SEQUENCER, "Add expected fixed size " & to_string(N_PACKETS) & " packets to Recv Queue");

        for i in 0 to N_PACKETS loop
          avalon_st_expect(AVALON_ST_VVCT, AURORA_RX_IDX, MAX_MSG(MAX_MSG'length - 1 downto i), "Receiving "&to_string(MAX_MSG'length - i));
        end loop;

          wait for 1 us;

        for i in 0 to N_PACKETS loop
          avalon_st_transmit(AVALON_ST_VVCT, AURORA_TX_IDX, MAX_MSG(MAX_MSG'length - 1 downto i), "Transmitting msg "&to_string(MAX_MSG'length - i));
        end loop;



        wait for 5 us;
      end loop;

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
