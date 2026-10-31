--! @file crc_tb.vhdl
--! @brief crc_tb
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 10-07-2025 Created
--! @version 0.2
--! @copyright CERN 2025
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

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
  use colibri.poly.all;

use work.comms_tb_pkg.all;

-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

entity crc_tb is
  generic (
    RUNNER_CFG        : string;
    g_CRC_POLY_LENGTH : natural                                          := 32;
    g_CRC_POLY_STRING : string                                           := "04c11db7";
    g_N_PACKETS       : natural                                          := 5;
    g_PACKET_SIZE     : natural                                          := 50;
    g_DATA_WIDTH      : positive                                         := 32;
    g_INIT_VAL        : std_logic_vector(g_CRC_POLY_LENGTH - 1 downto 0) := (others => '0');
    g_INVERT_IN       : boolean                                          := true;
    g_INVERT_OUT      : boolean                                          := true
  );
end entity crc_tb;

architecture bench of crc_tb is

  constant c_CRC_POLY       : std_logic_vector(g_CRC_POLY_LENGTH downto 0)     := '0' & string_to_slv(g_CRC_POLY_STRING, g_CRC_POLY_LENGTH);
  constant c_CRC_POLY_TRUNC : std_logic_vector(g_CRC_POLY_LENGTH - 1 downto 0) := string_to_slv(g_CRC_POLY_STRING, g_CRC_POLY_LENGTH);
  constant c_XOR_OUT        : std_logic_vector(g_CRC_POLY_LENGTH - 1 downto 0) := (others => '1');

  shared variable acov : t_coverpoint;

begin

  crc_th_inst : entity work.crc_th
    generic map (
      g_DATA_WIDTH => g_DATA_WIDTH,
      g_CRC_POLY   => c_CRC_POLY_TRUNC,
      g_INIT_VAL   => g_INIT_VAL,
      g_INVERT_IN  => g_INVERT_IN,
      g_INVERT_OUT => g_INVERT_OUT,
      g_XOR_OUT    => c_XOR_OUT
    );

  proc_sequencer : process is

    variable v_size    : natural;
    variable v_test    : std_logic_vector(g_PACKET_SIZE * 8 - 1 downto 0);
    variable v_msg     : t_slv_array(0 to g_PACKET_SIZE - 1)(7 downto 0);
    variable v_msg_ref : t_slv_array(0 to g_PACKET_SIZE - 1)(7 downto 0);
    variable v_crc     : std_logic_vector(g_CRC_POLY_LENGTH - 1 downto 0);

  begin

    ---------------- VUNIT SETUP ---------------
    test_runner_setup(runner, RUNNER_CFG);
    info("--- Configuration: " & to_string(g_PACKET_SIZE) & "B "& to_string(g_N_PACKETS)&" packets");
    info("--- Data Width: " & to_string(g_DATA_WIDTH)&" b");
    info("--- CRC Polynomial: 0x" & to_hstring(c_CRC_POLY) & " size " & to_string(g_CRC_POLY_LENGTH));
    ---------------- UVVM SETUP ----------------
    await_uvvm_initialization(VOID);

    disable_log_msg(VVC_BROADCAST, ID_PACKET_DATA);
    log(ID_LOG_HDR, "Configuring VVCs");
    -- clocks setup
    start_clock(CLOCK_GENERATOR_VVCT, c_CLK_GEN, "Starting clock");
    log(ID_SEQUENCER, "Waiting for reset propagation");
    wait for c_CLK_PERIOD * 4;
    --
    if run("crc") then
      -- create coverage bins
      acov.add_bins(bin_range(1,g_PACKET_SIZE), g_N_PACKETS);
      -- coverage loop
      while (not acov.coverage_completed(BINS_AND_HITS)) loop
        v_size := acov.rand(SAMPLE_COV);
        v_test := random(v_test'length);
        v_msg  := to_byte_array(v_test);

        -- test in inversion
        if (g_INVERT_IN) then

          for i in 0 to g_PACKET_SIZE - 1 loop
            v_msg_ref(i) := invert_bit_order(v_msg(i));
          end loop;

        else
          v_msg_ref := v_msg;
        end if;

        v_crc := generate_crc(v_msg_ref(0 to v_size - 1), g_INIT_VAL, c_CRC_POLY) xor c_XOR_OUT;

        -- test crc inversion
        if (g_INVERT_OUT) then
          v_crc := invert_bit_order(v_crc);
        end if;

        axistream_expect(AXISTREAM_VVCT, c_AXIS_CRC_IDX, v_crc, "exp CRC "&to_hstring(v_crc));

        avalon_st_transmit(AVALON_ST_VVCT, c_AV_ST_SRC_IDX,
                           v_msg(0 to v_size - 1),
                           "TX msg");

        avalon_st_expect(AVALON_ST_VVCT, c_AV_ST_SNK_IDX,
                         v_msg(0 to v_size - 1),
                         "RX "&to_string(v_msg(0 to v_size - 1)));

        await_completion(AVALON_ST_VVCT, c_AV_ST_SNK_IDX, 10 us);

      end loop;

    end if;

    -- UVVM cleanup
    await_completion(AVALON_ST_VVCT, c_AV_ST_SRC_IDX, 10 us);
    await_completion(AVALON_ST_VVCT, c_AV_ST_SNK_IDX, 10 us);
    report_alert_counters(FINAL);

    -- VUnit cleanup
    test_runner_cleanup(runner);

  end process proc_sequencer;

end architecture bench;
