-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

--
library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.com_context;
  context vunit_lib.data_types_context;
  use vunit_lib.avalon_stream_pkg.all;
  use vunit_lib.stream_master_pkg.all;
  use vunit_lib.stream_slave_pkg.all;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_clock_generator;
  context bitvis_vip_clock_generator.vvc_context;

library bitvis_vip_i2c;
  context bitvis_vip_i2c.vvc_context;

library colibri;
  context colibri.common;
use work.tb_pkg.all;

entity i2c_controller_tb is
  generic (
    RUNNER_CFG : string
  );
end entity i2c_controller_tb;

architecture sim of i2c_controller_tb is

  constant TEST_LOOP_NUM : natural := 10;

  shared variable my_coverpoint : t_coverpoint;

begin

  test_harness : entity work.i2c_controller_th(sim);

  proc_sequencer : process is

    variable tmp   : std_logic_vector(7 downto 0);
    variable rword : t_slv_array(2 downto 0)(7 downto 0);

    function convert_byte_pullup (val : std_logic_vector(7 downto 0)) return std_logic_vector is

      variable ret : std_logic_vector(7 downto 0);

    begin

      for i in val'range loop

        if (val(i) = 'H' or val(i) = '1') then
          ret(i) := '1';
        else
          ret(i) := '0';
        end if;

      end loop;

      return ret;

    end function convert_byte_pullup;

    procedure randomize_rword (
      variable cp    : inout t_coverpoint;
      variable rword : inout t_slv_array
    ) is
    begin

      for i in rword'range loop
        rword(i) := std_logic_vector(to_unsigned(cp.rand(NO_SAMPLE_COV), rword(i)'length));
      end loop;

    end procedure randomize_rword;

    procedure sample_rword (
      variable cp    : inout t_coverpoint;
      variable rword : in t_slv_array
    ) is
    begin

      for i in rword'range loop
        cp.sample_coverage(to_integer(unsigned(rword(i))));
      end loop;

    end procedure sample_rword;

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
    my_coverpoint.add_bins(bin_range(0,255,0));
    -- TEST : Encode Decode behaviour
    if run("i2c_byte_write") then
      log(ID_SEQUENCER, "requesting a write");

      for i in 0 to TEST_LOOP_NUM - 1 loop
        randomize_rword(my_coverpoint, rword(0 downto 0));
        i2c_slave_check(I2C_VVCT, c_I2C_IDX, rword(0), "expecting data from master");
        push_avalon_stream(net, c_avalon_source_stream, rword(0), '0', '0');
        await_completion(I2C_VVCT, c_I2C_IDX, 10 us);
        sample_rword(my_coverpoint, rword(0 downto 0));
      end loop;

    elsif run("i2c_multi_byte_read") then
      log(ID_SEQUENCER, "requesting 2 read");

      for i in 0 to TEST_LOOP_NUM - 1 loop
        randomize_rword(my_coverpoint, rword(1 downto 0));
        push_avalon_stream(net, c_avalon_source_stream, x"aa", '1', '0');
        push_avalon_stream(net, c_avalon_source_stream, x"aa", '1', '0');
        log(ID_SEQUENCER, "Device transmit 2 read");
        i2c_slave_transmit(I2C_VVCT, c_I2C_IDX, rword(1 downto 0), "sending bytes to master");
        pop_stream(net, c_slave_stream, tmp);
        tmp := convert_byte_pullup(tmp);
        log(ID_SEQUENCER, "Received: "&to_hstring(tmp));
        check(tmp = rword(1), "check read result");
        pop_stream(net, c_slave_stream, tmp);
        tmp := convert_byte_pullup(tmp);
        log(ID_SEQUENCER, "Received: "&to_hstring(tmp));
        check(tmp = rword(0), "check read result");
        await_completion(I2C_VVCT, c_I2C_IDX, 10 us);
        sample_rword(my_coverpoint, rword(1 downto 0));
      end loop;

    elsif run("i2c_write_then_read") then
      log(ID_SEQUENCER, "write then read");

      for i in 0 to TEST_LOOP_NUM - 1 loop
        randomize_rword(my_coverpoint, rword(1 downto 0));
        i2c_slave_check(I2C_VVCT, c_I2C_IDX, rword(0), "expecting data from master");
        i2c_slave_transmit(I2C_VVCT, c_I2C_IDX, rword(1), "sending bytes to master");
        push_avalon_stream(net, c_avalon_source_stream, rword(0), '0', '0');
        push_avalon_stream(net, c_avalon_source_stream, x"aa", '1', '0');
        pop_stream(net, c_slave_stream, tmp);
        tmp := convert_byte_pullup(tmp);
        log(ID_SEQUENCER, "Received: "&to_hstring(tmp));
        check(tmp = rword(1), "check read result");
        await_completion(I2C_VVCT, c_I2C_IDX, 10 us);
        sample_rword(my_coverpoint, rword(1 downto 0));
      end loop;

    elsif run("i2c_read_then_write") then
      log(ID_SEQUENCER, "read then write");

      for i in 0 to TEST_LOOP_NUM - 1 loop
        randomize_rword(my_coverpoint, rword(1 downto 0));
        i2c_slave_transmit(I2C_VVCT, c_I2C_IDX, rword(0), "sending bytes to master");
        i2c_slave_check(I2C_VVCT, c_I2C_IDX, rword(1), "expecting data from master");
        push_avalon_stream(net, c_avalon_source_stream, x"aa", '1', '0');
        push_avalon_stream(net, c_avalon_source_stream, rword(1), '0', '0');
        pop_stream(net, c_slave_stream, tmp);
        tmp := convert_byte_pullup(tmp);
        log(ID_SEQUENCER, "Received: "&to_hstring(tmp));
        check(tmp = rword(0), "check read result");
        await_completion(I2C_VVCT, c_I2C_IDX, 10 us);
        sample_rword(my_coverpoint, rword(1 downto 0));
      end loop;

    elsif run("i2c_multi_byte_write") then
      log(ID_SEQUENCER, "requesting multi-byte write");

      for i in 0 to TEST_LOOP_NUM - 1 loop
        randomize_rword(my_coverpoint, rword);
        i2c_slave_check(I2C_VVCT, c_I2C_IDX, rword, "expecting 3-byte write from master");
        push_avalon_stream(net, c_avalon_source_stream, rword(2), '0', '0');
        push_avalon_stream(net, c_avalon_source_stream, rword(1), '0', '0');
        push_avalon_stream(net, c_avalon_source_stream, rword(0), '0', '0');
        await_completion(I2C_VVCT, c_I2C_IDX, 10 us);
        sample_rword(my_coverpoint, rword);
      end loop;

    end if;

    my_coverpoint.delete_coverpoint(VOID);
    report_alert_counters(FINAL);

    -- VUnit cleanup
    test_runner_cleanup(runner);

  end process proc_sequencer;

  test_runner_watchdog(runner, 10 ms);

end architecture sim;
