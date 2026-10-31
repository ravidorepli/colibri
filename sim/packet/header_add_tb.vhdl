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

entity header_add_tb is
  generic (
    RUNNER_CFG     : string;
    g_N_PACKETS    : natural;
    g_PACKET_SIZE  : natural;
    g_DATA_WIDTH   : natural;
    g_HEADER_BYTES : natural
  );
end entity header_add_tb;

architecture sim of header_add_tb is

  signal          acov      : CoverageIDType;
  constant        N_PACKETS : natural := g_N_PACKETS;
  constant        N_BYTES   : natural := g_PACKET_SIZE + g_HEADER_BYTES;
  shared variable v_rv      : RandomPType;

begin

  test_harness : entity work.header_add_th(sim)
    generic map (
      g_HEADER_BYTES => g_HEADER_BYTES,
      g_DATA_WIDTH   => g_DATA_WIDTH
    );

  proc_seq : process is

    variable v_pkt_cnt : natural := 0;
    variable v_size    : natural;
    variable v_test    : std_logic_vector(N_BYTES * 8 - 1 downto 0);
    variable v_msg     : t_slv_array(0 to N_BYTES - 1)(7 downto 0);

    variable v_header : std_logic_vector(g_HEADER_BYTES * 8 - 1 downto 0);

  begin

    ---------------- VUNIT SETUP ---------------
    test_runner_setup(runner, RUNNER_CFG);

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

    if run("header_random") then
      -- generate test bins
      AddBins(acov, GenBin(g_HEADER_BYTES,N_BYTES,N_PACKETS));

      loop
        -- get random size from bins
        v_size   := GetRandPoint(acov);
        v_test   := v_rv.RandSlv(N_BYTES * 8);
        -- get header from stimuli vector
        v_header :=v_test(v_test'left downto v_test'length - g_HEADER_BYTES * 8);

        -- push it to the DUT
        axistream_transmit(AXISTREAM_VVCT, AXIS_ETH_HEADER_IDX,
                           to_byte_array(v_header),
                           "setting header");
        wait for 3 * CLK_PERIOD_MAIN;


        -- push the data through
        v_msg     :=  to_byte_array(v_test);
        axistream_transmit(AXISTREAM_VVCT, AXIS_TX_IDX, v_msg(g_HEADER_BYTES to v_size), "TX"&to_string(v_pkt_cnt) &": size "&to_string(v_size));
        -- check result
        axistream_expect(AXISTREAM_VVCT, AXIS_RX_IDX, v_msg(0 to v_size), "Receiving "&to_string(v_pkt_cnt));
        await_completion(VVC_BROADCAST, 10 ms, "Wait for all the VVCs to finish");
        v_pkt_cnt := v_pkt_cnt + 1;
        ICover(acov, v_size);
        exit when IsCovered(acov);
      end loop;

    end if;

    -- UVVM cleanup
    await_completion(VVC_BROADCAST, 10 ms, "Wait for all the VVCs to finish");
    wait for 3 * CLK_PERIOD_MAIN;

    writeBin(acov);
    report_alert_counters(FINAL);

    -- VUnit cleanup
    test_runner_cleanup(runner);

  end process proc_seq;

end architecture sim;
