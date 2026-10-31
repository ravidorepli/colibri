--! @title UART receiver module
--! @file uart_rx.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 20-03-2024
--! @version 0.1

--! This module implements a simple uart receiver.
--! Release log:
--! - 0.1 first release
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

entity uart_rx is
  generic (
    g_CLOCK_PERIOD : time    := 100 ns;
    g_BAUD_RATE    : natural := 115200
  );
  port (
    clk_i      : in    std_logic;
    reset_i    : in    std_logic;
    --! @virtualbus AXIS @dir in transmit
    rx_data_o  : out   std_logic_vector(7 downto 0);
    rx_valid_o : out   std_logic;
    --! @end
    rx_pin_i   : in    std_logic
  );
end entity uart_rx;

architecture rtl of uart_rx is

  constant c_SER_CYCLES : integer := integer((1 sec / g_BAUD_RATE) / g_CLOCK_PERIOD);

  type fsm_t is (S_RESET, S_IDLE, S_START, S_DATA, S_STOP);

  type sig_t is record
    state  : fsm_t;
    valid  : std_logic;
    clk_en : std_logic;
    byte   : std_logic_vector(7 downto 0);
    count  : natural range 0 to 8;
  end record sig_t;

  constant c_FSM_INIT     : sig_t :=
  (
    state  => S_IDLE,
    valid  => '0',
    clk_en => '0',
    byte   => (others => '0'),
    count  => 0
  );
  signal   rx_d           : std_logic;
  signal   rx_reg         : std_logic;
  signal   rreg           : sig_t := c_FSM_INIT;
  signal   rcmb           : sig_t;
  signal   serclk         : std_logic;
  signal   dataclk        : std_logic;
  signal   dataclk_rising : std_logic;
  -- clock generator
  signal clk_count        : natural range 0 to c_SER_CYCLES / 2 - 1 := 0;
  signal clk_delay        : std_logic_vector(c_SER_CYCLES / 4 - 1 downto 0);
  -- SDC constraints for Altera
  attribute preserve                          : boolean;
  attribute altera_attribute                  : string;
  attribute altera_attribute of rx_d : signal is
     "-name SYNCHRONIZER_IDENTIFICATION ""FORCED IF ASYNCHRONOUS""";
  attribute preserve of rx_d         : signal is true;
  -- SDC constraints for Xilinx
  attribute async_reg                  : string;
  attribute async_reg of rx_d : signal is "TRUE";

begin

  proc_synch : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        rx_d   <= '1';
        rx_reg <= '1';
      else
        rx_d   <= rx_pin_i;
        rx_reg <= rx_d;
      end if;
    end if;

  end process proc_synch;

  proc_clk_gen : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        clk_delay      <= (others => '0');
        clk_count      <= 0;
        dataclk_rising <= '0';
        serclk         <= '0';
        dataclk        <= '0';
      else
        --! internal counter for clock division
        if (rreg.clk_en = '1') then
          clk_delay <= serclk & clk_delay(clk_delay'left downto 1);
          if (clk_count = c_SER_CYCLES / 2 - 1) then
            clk_count <= 0;
            serclk    <= not serclk;
          else
            clk_count <= clk_count + 1;
          end if;
        else
          clk_count <= 0;
          serclk    <= '1';
          clk_delay <= (others => '0');
        end if;
        -- rising edge pulse to capture data
        if (clk_delay(0) = '1' and dataclk = '0') then
          dataclk_rising <= '1';
        else
          dataclk_rising <= '0';
        end if;
        dataclk <= clk_delay(0);
      end if;
    end if;

  end process proc_clk_gen;

  proc_fsm_cmb : process (all) is

    variable v_int : sig_t;

  begin

    v_int := rreg;

    case rreg.state is

      when S_RESET =>
        v_int := c_FSM_INIT;

      when S_IDLE =>
        v_int.count := 0;
        -- start bit seen
        if (rx_reg = '0') then
          v_int.clk_en := '1';
          v_int.state  := S_START;
        end if;

      when S_START =>

        if (dataclk_rising = '1' and rx_reg = '0') then
          v_int.count := rreg.count + 1;
          v_int.byte  := rx_reg & rreg.byte(rreg.byte'left downto 1);
          v_int.state := S_DATA;
        end if;

      when S_DATA =>

        if (dataclk_rising = '1') then
          v_int.byte := rx_reg & rreg.byte(rreg.byte'left downto 1);
          if (rreg.count = 8) then
            v_int.valid := '1';
            v_int.state := S_STOP;
          else
            v_int.count := rreg.count + 1;
          end if;
        end if;

      when S_STOP =>
        v_int.valid := '0';

        if (dataclk_rising = '1') then
          v_int.clk_en := '0';
          v_int.state  := S_IDLE;
        end if;

    end case;

    if (reset_i = '1') then
      v_int.state := S_RESET;
    end if;

    rcmb <= v_int;

  end process proc_fsm_cmb;

  rx_data_o  <= rreg.byte;
  rx_valid_o <= rreg.valid;
  rreg       <= rcmb when rising_edge(clk_i);

end architecture rtl;
