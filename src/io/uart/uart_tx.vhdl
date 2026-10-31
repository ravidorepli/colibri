--! @title UART transmitter module
--! @file uart_tx.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 20-03-2024
--! @version 0.1

--! This module implements a simple uart transmitter.
--! Release log:
--! - 0.1 first release
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

entity uart_tx is
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
    tx_pin_o   : out   std_logic
  );
end entity uart_tx;

architecture rtl of uart_tx is

  constant c_SER_CYCLES : integer                                 := integer((1 sec / g_BAUD_RATE) / g_CLOCK_PERIOD);
  signal   clk_count    : natural range 0 to c_SER_CYCLES / 2 - 1 := 0;

  type fsm_t is (S_RESET, S_IDLE, S_START, S_DATA, S_STOP);

  type sig_t is record
    state : fsm_t;
    tx    : std_logic;
    byte  : std_logic_vector(7 downto 0);
    count : natural range 0 to 8;
  end record sig_t;

  constant c_FSM_INIT    : sig_t :=
  (
    state => S_IDLE,
    tx    => '1',
    byte  => (others => '0'),
    count => 0
  );
  signal   rreg          : sig_t := c_FSM_INIT;
  signal   rcmb          : sig_t;
  signal   serclk        : std_logic;
  signal   serclk_rising : std_logic;

begin

  proc_clk_gen : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        clk_count     <= 0;
        serclk_rising <= '0';
        serclk        <= '0';
      else
        serclk_rising <= '0';
        --! internal counter for clock division
        if (clk_count = c_SER_CYCLES / 2 - 1) then
          clk_count <= 0;
          serclk    <= not serclk;
          if (serclk = '0') then
            serclk_rising <= '1';
          end if;
        else
          clk_count <= clk_count + 1;
        end if;
      end if;
    end if;

  end process proc_clk_gen;

  proc_fsm_cmb : process (all) is

    variable v_int : sig_t;

  begin

    v_int      := rreg;
    tx_ready_o <= '0';

    case rreg.state is

      when S_RESET =>
        v_int := c_FSM_INIT;

      when S_IDLE =>

        if (serclk_rising) then
          tx_ready_o <= '1';

          if (tx_valid_i = '1') then
            v_int.byte  := tx_data_i;
            v_int.tx    := '0';
            v_int.count := 0;
            v_int.state := S_START;
          end if;
        end if;

      when S_START =>

        if (serclk_rising) then
          v_int.tx    := rreg.byte(0);
          v_int.byte  := "0" & rreg.byte(rreg.byte'left downto 1);
          v_int.count := rreg.count + 1;
          v_int.state := S_DATA;
        end if;

      when S_DATA =>

        if (serclk_rising) then
          v_int.tx   := rreg.byte(0);
          v_int.byte := "0" & rreg.byte(rreg.byte'left downto 1);
          if (rreg.count = 8) then
            v_int.tx    := '1';
            v_int.state := S_STOP;
          else
            v_int.count := rreg.count + 1;
          end if;
        end if;

      when S_STOP =>

        if (serclk_rising) then
          v_int.state := S_IDLE;
        end if;

    end case;

    if (reset_i = '1') then
      v_int.state := S_RESET;
    end if;

    rcmb <= v_int;

  end process proc_fsm_cmb;

  tx_pin_o <= rreg.tx;
  rreg     <= rcmb when rising_edge(clk_i);

end architecture rtl;
