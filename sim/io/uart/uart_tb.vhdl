-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_clock_generator;
  context bitvis_vip_clock_generator.vvc_context;

--
library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.com_context;
  context vunit_lib.data_types_context;
  use vunit_lib.avalon_stream_pkg.all;
  use vunit_lib.stream_master_pkg.all;
  use vunit_lib.stream_slave_pkg.all;

use work.tb_pkg.all;

entity uart_tb is
  generic (
    RUNNER_CFG : string
  );
end entity uart_tb;

architecture sim of uart_tb is

begin

  test_harness : entity work.uart_th(sim);

  proc_main : process is

    variable tmp  : std_logic_vector(7 downto 0);
    variable send : std_logic_vector(7 downto 0);

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
    if run("uart") then

      for i in 0 to 10 loop
        send := std_logic_vector(to_unsigned(i, 8) + x"A");
        log(ID_SEQUENCER, "Write "&to_hstring(send));
        push_stream(net, c_MASTER_STREAM, send);
        pop_stream(net, c_slave_stream, tmp);
        log(ID_SEQUENCER, "Received: "&to_hstring(tmp));
        check(tmp = send, "check read result");
      end loop;

    end if;

    report_alert_counters(FINAL);

    -- VUnit cleanup
    test_runner_cleanup(runner);
    test_runner_setup(runner, runner_cfg);

  end process proc_main;

  test_runner_watchdog(runner, 10 ms);

end architecture sim;
