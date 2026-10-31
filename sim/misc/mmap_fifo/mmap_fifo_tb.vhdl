-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

--! @file mmap_fifo_tb.vhdl
--! @brief Automated Testbench for MMAP FIFO
--! @author Alberto Perro
--! @date 03-03-2026 Updated
--! @version 1.1
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.osvvmcontext;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_clock_generator;
  context bitvis_vip_clock_generator.vvc_context;

library bitvis_vip_avalon_st;
  context bitvis_vip_avalon_st.vvc_context;

library bitvis_vip_wishbone;
  context bitvis_vip_wishbone.vvc_context;

library vunit_lib;
  context vunit_lib.vunit_context;

library colibri;
  context colibri.common;

use work.mmap_fifo_sim_pkg.all;

--==================================================================================================
--! @brief Automated testbench for the mmap_fifo entity
--! @details
--! This testbench verifies the MMAP to Stream (TX) and Stream to MMAP (RX) FIFO logic using:
--! - **UVVM VVCs**: Wishbone and Avalon-ST verification components for bus abstraction.
--! - **VUnit**: Test runner management and configuration.
--! - **OSVVM**: Randomization for packet sizes and data content.
--! The TB checks for the normal behaviour (TX and RX), and the Interrupt processing.
--==================================================================================================

entity mmap_fifo_tb is
  generic (
    RUNNER_CFG : string
  );
end entity mmap_fifo_tb;

architecture bench of mmap_fifo_tb is

  constant c_PACKET_SIZE : integer := (c_NUM_WORDS * c_STREAM_DATA_WIDTH / 8) - 1;
  constant c_TEST_SIZE   : integer := 10;
  constant c_OVF_BYTES   : integer := (c_STREAM_DATA_WIDTH / 8) * 4;

  -- Register Offsets (derived from RDL)
  constant ADDR_TX_CTRL : unsigned(31 downto 0) := 32x"00";
  constant ADDR_TX_IER  : unsigned(31 downto 0) := 32x"04";
  constant ADDR_TX_ISR  : unsigned(31 downto 0) := 32x"08";
  constant ADDR_TX_LEN  : unsigned(31 downto 0) := 32x"10";
  constant ADDR_TX_DATA : unsigned(31 downto 0) := 32x"14";
  constant ADDR_TX_DEST : unsigned(31 downto 0) := 32x"18";

  constant ADDR_RX_CTRL : unsigned(31 downto 0) := 32x"20";
  constant ADDR_RX_IER  : unsigned(31 downto 0) := 32x"24";
  constant ADDR_RX_ISR  : unsigned(31 downto 0) := 32x"28";
  constant ADDR_RX_LEN  : unsigned(31 downto 0) := 32x"30";
  constant ADDR_RX_DATA : unsigned(31 downto 0) := 32x"34";
  constant ADDR_RX_SRC  : unsigned(31 downto 0) := 32x"38";

  signal intr : std_logic;

begin

  th : entity work.mmap_fifo_th
    port map (
      intr_o => intr
    );

  proc_main : process is

    variable v_size : natural;
    variable v_chan : natural;
    variable v_test : std_logic_vector((c_PACKET_SIZE + c_OVF_BYTES) * 8 - 1 downto 0);
    variable v_msg  : t_slv_array(0 to (c_PACKET_SIZE + c_OVF_BYTES) - 1)(7 downto 0);

    function pack_word (arr : t_slv_array; idx : integer) return std_logic_vector is

      variable v_ret : std_logic_vector(31 downto 0) := (others => '0');

    begin

      for k in 0 to 3 loop

        if ((idx + k) <= arr'high) then
          v_ret(31 - (k * 8) downto 24 - (k * 8)) := arr(idx + k);
        end if;

      end loop;

      return v_ret;

    end function pack_word;

    procedure write_packet (
      v_pkt : t_slv_array;
      dest  : integer
    ) is

      constant c_PKT_WORDS : integer := div_ceil(v_pkt'length, 4);

    begin

      wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_TX_DEST, std_logic_vector(to_unsigned(dest, 32)), "Set Dest ID");

      for i in 0 to c_PKT_WORDS - 1 loop
        wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_TX_DATA, pack_word(v_pkt, i * 4), "Write Word");
      end loop;

    end procedure write_packet;

    procedure read_packet (
      v_pkt : t_slv_array;
      src   : integer
    ) is

      constant c_PKT_WORDS : integer := div_ceil(v_pkt'length, 4);

    begin

      wishbone_check(WISHBONE_VVCT, c_WBM, ADDR_RX_ISR, 32x"1", "Check Read Complete");
      wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_RX_ISR, 32x"1", "Clear Interrupt");
      wishbone_check(WISHBONE_VVCT, c_WBM, ADDR_RX_LEN, std_logic_vector(to_unsigned(v_pkt'length, 32)), "Verify Size");
      wishbone_check(WISHBONE_VVCT, c_WBM, ADDR_RX_SRC, std_logic_vector(to_unsigned(src, 32)), "Verify Source");

      for i in 0 to c_PKT_WORDS - 1 loop
        wishbone_check(WISHBONE_VVCT, c_WBM, ADDR_RX_DATA, pack_word(v_pkt, i * 4), "Check Data Word");
      end loop;

    end procedure read_packet;

    procedure init_dut is
    begin

      wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_TX_CTRL, 32x"1", "Reset TX");
      wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_TX_IER,  32x"0", "Disable TX Int");
      wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_TX_ISR,  32x"FFFFFFF", "Clear TX Status");
      wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_RX_IER,  32x"0", "Disable RX Int");
      wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_RX_ISR,  32x"FFFFFFF", "Clear RX Status");
      await_completion(WISHBONE_VVCT, c_WBM, 10 us);

    end procedure init_dut;

  begin

    test_runner_setup(runner, RUNNER_CFG);
    await_uvvm_initialization(VOID);

    -- Cleanup logs
    disable_log_msg(VVC_BROADCAST, ID_PACKET_DATA);
    disable_log_msg(VVC_BROADCAST, ID_POS_ACK);

    start_clock(CLOCK_GENERATOR_VVCT, c_CLK_MAIN, "Main Clock");
    start_clock(CLOCK_GENERATOR_VVCT, c_CLK_WB,   "Wishbone Clock");

    wait for c_CLK_PERIOD * 5;
    init_dut;

    v_test := random(v_test'length);
    v_msg  := to_byte_array(v_test);
    -- =========================================================================
    -- TX TESTS
    -- =========================================================================
    if run("tx_simple") then

      for i in 0 to c_TEST_SIZE - 1 loop
        v_size := random(1, c_PACKET_SIZE);
        v_chan := random(0, c_NUM_CH - 1);

        wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_TX_IER, 32x"1", "Enable TX Complete IRQ");
        write_packet(v_msg(0 to v_size - 1), v_chan);
        wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_TX_LEN, std_logic_vector(to_unsigned(v_size, 32)), "Trigger TX");

        avalon_st_expect(AVALON_ST_VVCT, c_AVST_MM2S, std_logic_vector(to_unsigned(v_chan, 2)), v_msg(0 to v_size - 1), "Check AVST");
        await_completion(VVC_BROADCAST, 10 us);
        --
        await_value(intr, '1', 0 ns, 1 us, "Wait IRQ");
        wishbone_check(WISHBONE_VVCT, c_WBM, ADDR_TX_ISR, 32x"1", "Check TX Complete IRQ");
        wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_TX_ISR, 32x"f", "Clear IRQ");
      end loop;

    elsif run("tx_overflow") then
      v_size := random(c_PACKET_SIZE + 1, c_PACKET_SIZE + c_OVF_BYTES);
      wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_TX_IER, 32x"2", "Enable OVF Int");
      write_packet(v_msg(0 to v_size - 1), 0);
      wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_TX_LEN, std_logic_vector(to_unsigned(v_size, 32)), "Trigger TX");
      await_value(intr, '1', 0 ns, 1 us, "Wait OVF IRQ");
      wishbone_check(WISHBONE_VVCT, c_WBM, ADDR_TX_ISR, 32x"2", "Verify OVF Flag");
    elsif run("tx_wrong_size") then
      v_size := random(1, c_PACKET_SIZE - 20);
      wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_TX_IER, 32x"4", "Enable Len Err Int");
      write_packet(v_msg(0 to v_size - 1), 0);
      wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_TX_LEN, std_logic_vector(to_unsigned(v_size + 10, 32)), "Trig Err");
      await_value(intr, '1', 0 ns, 10 us, "Wait Err IRQ");
      wishbone_check(WISHBONE_VVCT, c_WBM, ADDR_TX_ISR, 32x"4", "Check Len Err Flag");
    -- =========================================================================
    -- RX TESTS
    -- =========================================================================
    elsif run("rx_simple") then

      for i in 0 to c_TEST_SIZE - 1 loop
        v_size := random(1, c_PACKET_SIZE);
        v_chan := random(0, c_NUM_CH - 1);
        wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_RX_IER, 32x"1", "Enable RX Int");
        avalon_st_transmit(AVALON_ST_VVCT, c_AVST_S2MM, std_logic_vector(to_unsigned(v_chan, 2)), v_msg(0 to v_size - 1), "TX Stream");
        await_completion(VVC_BROADCAST, 10 us);
        await_value(intr, '1', 0 ns, 1 us, "Wait IRQ");
        read_packet(v_msg(0 to v_size - 1), v_chan);
      end loop;

    elsif run("rx_overflow") then
      wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_RX_IER, 32x"3", "Enable RX Done + OVF Int");
      v_size := random(c_PACKET_SIZE + 1, c_PACKET_SIZE + c_OVF_BYTES);
      avalon_st_transmit(AVALON_ST_VVCT, c_AVST_S2MM, 2x"0", v_msg(0 to v_size - 1), "TX OVF Stream");
      await_value(intr, '1', 0 ns, 10 us, "Wait IRQ");
      wishbone_check(WISHBONE_VVCT, c_WBM, ADDR_RX_ISR, 32x"2", "Check RX OVF Flag");
    elsif run("rx_empty") then
      wishbone_write(WISHBONE_VVCT, c_WBM, ADDR_RX_IER, 32x"4", "Enable Empty Int");
      wishbone_read(WISHBONE_VVCT, c_WBM, ADDR_RX_DATA, "Read Empty");
      await_value(intr, '1', 0 ns, 1 us, "Wait IRQ");
      wishbone_check(WISHBONE_VVCT, c_WBM, ADDR_RX_ISR, 32x"4", "Verify Empty Flag");
    end if;

    await_completion(VVC_BROADCAST, 10 us);
    report_alert_counters(FINAL);
    test_runner_cleanup(runner);

  end process proc_main;

  test_runner_watchdog(runner, 10 ms);

end architecture bench;
