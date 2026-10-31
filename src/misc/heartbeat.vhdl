--==================================================================================================
--! @brief Clock Heartbeat generator
--!
--!  This module produces a divided clock signal, which is used as a heartbeat
--!  signal, indicating the clock is active. Most common usecase is to use
--!  the slow `heartbeat_o` signal to drive an LED.
--!
--!  The frequency of the output signal is determined by the input clock
--!  frequency (set by `g_CLOCK_PERIOD`) and the beat frequency (`g_BEAT_PERIOD`).
--!
--! Change Log:
--! - 0.2 (alperro) add generic for beat period, use counter entity from `common`
--! - 0.1 (mvodnik) first release
--!
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 31-01-2024 Created
--! @version 0.2
--! @copyright CERN 2024
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

----------------------------------------------------------------------------------------------------

entity heartbeat is
  generic (
    --! customizable heart beat period
    g_BEAT_PERIOD : time := 1 sec;
    --! main clock period
    g_CLK_PERIOD  : time := 8 ns
  );
  port (
    --! Clock and reset
    clk_i   : in    std_logic;
    reset_i : in    std_logic;

    --! Heartbeat output signal
    heartbeat_o : out   std_logic
  );
end entity heartbeat;

----------------------------------------------------------------------------------------------------

architecture rtl of heartbeat is

  --! Maximum counter value, to count half of the HB period
  constant c_CNT_MAX : positive := (g_BEAT_PERIOD / g_CLK_PERIOD) / 2;

  --! pulse to invert output
  signal pulse_flip : std_logic;

begin

  counter_inst : entity work.counter
    generic map (
      g_MODULO => c_CNT_MAX
    )
    port map (
      clk_i        => clk_i,
      reset_i      => reset_i,
      enable_i     => '1',
      value_o      => open,
      wraparound_o => pulse_flip
    );

  proc_out_driver : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        heartbeat_o <= '0';
      elsif (pulse_flip = '1') then
        heartbeat_o <= not heartbeat_o;
      end if;
    end if;

  end process proc_out_driver;

end architecture rtl;

----------------------------------------------------------------------------------------------------
