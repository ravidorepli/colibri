--! @title UART Controller module
--! @file uart.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 20-03-2024
--! @version 0.1

--! This module implements a simple uart controller.
--! Release log:
--! - 0.1 first release
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;

entity uart is
  generic (
    g_CLOCK_PERIOD : time    := 100 ns;
    g_BAUD_RATE    : natural := 115200
  );
  port (
    clk_i      : in    std_logic;
    reset_i    : in    std_logic;
    --! @virtualbus AXIS @dir in transmit
    tx_data_i  : in    std_logic_vector(7 downto 0);
    tx_valid_i : in    std_logic;
    tx_ready_o : out   std_logic;
    --! @end
    --! @virtualbus AXIS @dir in receive
    rx_data_o  : out   std_logic_vector(7 downto 0);
    rx_valid_o : out   std_logic;
    --! @end
    rx_pin_i   : in    std_logic;
    tx_pin_o   : out   std_logic
  );
end entity uart;

architecture rtl of uart is

begin

  uart_rx_inst : entity work.uart_rx
    generic map (
      g_CLOCK_PERIOD => g_CLOCK_PERIOD,
      g_BAUD_RATE    => g_BAUD_RATE
    )
    port map (
      clk_i      => clk_i,
      reset_i    => reset_i,
      rx_data_o  => rx_data_o,
      rx_valid_o => rx_valid_o,
      rx_pin_i   => rx_pin_i
    );

  uart_tx_inst : entity work.uart_tx
    generic map (
      g_CLOCK_PERIOD => g_CLOCK_PERIOD,
      g_BAUD_RATE    => g_BAUD_RATE
    )
    port map (
      clk_i      => clk_i,
      reset_i    => reset_i,
      tx_data_i  => tx_data_i,
      tx_valid_i => tx_valid_i,
      tx_ready_o => tx_ready_o,
      tx_pin_o   => tx_pin_o
    );

end architecture rtl;
