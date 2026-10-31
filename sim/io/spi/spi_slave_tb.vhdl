-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library vunit_lib;
  context vunit_lib.vunit_context;

library osvvm;
  use osvvm.randompkg.all;
  use osvvm.coveragepkg.all;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_clock_generator;
  context bitvis_vip_clock_generator.vvc_context;

library bitvis_vip_axistream;
  context bitvis_vip_axistream.vvc_context;

library bitvis_vip_spi;
  context bitvis_vip_spi.vvc_context;

library colibri;
  context colibri.common;
use work.tb_pkg.all;

entity spi_slave_tb is
  generic (
    RUNNER_CFG   : string;
    SCK_PHASE    : boolean := false;
    SCK_POLARITY : boolean := false
  );
end entity spi_slave_tb;

architecture sim of spi_slave_tb is

  -- osvvm random coverage pkg
  shared variable v_rv        : RandomPType;
  signal          v_cov       : CoverageIDType;
  constant        SL_PHASE    : std_logic := bool_to_sl(SCK_PHASE);
  constant        SL_POLARITY : std_logic := bool_to_sl(SCK_POLARITY);

begin

  test_harness : entity work.spi_slave_th(sim)
    generic map (
      g_SCK_PHASE    => sl_phase,
      g_SCK_POLARITY => sl_polarity
    );

  proc_main : process is

    variable tmp     : t_slv_array(0 downto 0)(7 downto 0);
    variable tmp_b   : t_slv_array(0 downto 0)(7 downto 0);
    variable point   : natural;
    variable point_b : natural;

  begin

    ---------------- VUNIT SETUP ---------------
    test_runner_setup(runner, RUNNER_CFG);
    --------------- OSVVM SETUP ----------------
    v_cov <= NewID("Coverage");
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

    if run("tx_only") then
      AddBins(v_cov, GenBin(0,255)); -- cover all bytes

      loop
        point  := GetRandPoint(v_cov);
        tmp(0) := std_logic_vector(to_unsigned(point, 8));
        log(ID_SEQUENCER, "Transmit "&to_hstring(tmp(0)));
        axistream_expect(AXISTREAM_VVCT, c_AXIS_SNK_IDX, tmp, "receiving from master "&to_string(point));
        spi_master_transmit_only (SPI_VVCT, c_SPI_IDX, tmp(0), "tx "&to_string(point));
        await_completion(AXISTREAM_VVCT, c_AXIS_SNK_IDX, 10 ms);
        await_completion(SPI_VVCT, c_SPI_IDX, 10 ms);
        ICover(v_cov, point);
        exit when IsCovered(v_cov);
      end loop;

    end if;

    if run("rx_only") then
      insert_delay(SPI_VVCT, c_SPI_IDX, 50 ns, "50 ns delay");
      AddBins(v_cov, GenBin(0,255)); -- cover all bytes

      loop
        point  := GetRandPoint(v_cov);
        tmp(0) := std_logic_vector(to_unsigned(point, 8));
        log(ID_SEQUENCER, "Receive "&to_hstring(tmp(0)));
        spi_master_check_only (SPI_VVCT, c_SPI_IDX, tmp(0), "rx "&to_string(point));
        axistream_transmit(AXISTREAM_VVCT, c_AXIS_SRC_IDX, tmp, "send to master "&to_string(point));
        await_completion(AXISTREAM_VVCT, c_AXIS_SNK_IDX, 10 ms);
        await_completion(SPI_VVCT, c_SPI_IDX, 10 ms);
        ICover(v_cov, point);
        exit when IsCovered(v_cov);
      end loop;

    end if;

    if run("tx_rx") then
      AddCross(v_cov, GenBin(0,15), GenBin(240,255));
      AddCross(v_cov, GenBin(240,255), GenBin(0,15));

      loop
        (point, point_b) := GetRandPoint(v_cov);
        tmp(0)           := std_logic_vector(to_unsigned(point, 8));
        tmp_b(0)         := std_logic_vector(to_unsigned(point_b, 8));
        log(ID_SEQUENCER, "Transmit "&to_hstring(tmp(0))&" and Receive "&to_hstring(tmp_b(0)));
        axistream_transmit(AXISTREAM_VVCT, c_AXIS_SRC_IDX, tmp, "send to master "&to_string(point));
        axistream_expect(AXISTREAM_VVCT, c_AXIS_SNK_IDX, tmp_b, "receiving from master "&to_string(point_b));
        spi_master_transmit_and_check(SPI_VVCT, c_SPI_IDX, tmp_b(0), tmp(0), "tx-rx"&to_string(point)&"-"&to_string(point_b));
        await_completion(AXISTREAM_VVCT, c_AXIS_SNK_IDX, 10 ms);
        await_completion(SPI_VVCT, c_SPI_IDX, 10 ms);
        ICover(v_cov, (point,point_b));
        exit when IsCovered(v_cov);
      end loop;

    end if;

    -- end if;
    await_completion(AXISTREAM_VVCT, c_AXIS_SNK_IDX, 10 ms);
    await_completion(SPI_VVCT, c_SPI_IDX, 10 ms);

    report_alert_counters(FINAL);

    WriteBin(v_cov);

    -- VUnit cleanup
    test_runner_cleanup(runner);
    test_runner_setup(runner, runner_cfg);

  end process proc_main;

  test_runner_watchdog(runner, 10 ms);

end architecture sim;
