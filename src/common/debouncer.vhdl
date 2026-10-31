--! @title Debouncer
--! @file debouncer.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 14-06-2024
--! @version 0.1

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
  use colibri.utils.all;

entity debouncer is
  generic (
    g_RESET_VAL     : std_logic_vector;
    g_DEBOUNCE_TIME : time := 10 ms;
    g_CLOCK_PERIOD  : time
  );
  port (
    clk_i   : in    std_logic;
    reset_i : in    std_logic;
    data_i  : in    std_logic_vector;
    data_o  : out   std_logic_vector
  );
end entity debouncer;

architecture rtl of debouncer is

  constant c_MODULO_DEBOUNCE : integer := div_ceil(g_DEBOUNCE_TIME, g_CLOCK_PERIOD);

  signal data_reg  : data_i'subtype;
  signal cnt_reset : std_logic;
  signal valid     : std_logic;

begin

  counter_inst : entity work.counter
    generic map (
      g_MODULO => c_MODULO_DEBOUNCE
    )
    port map (
      clk_i        => clk_i,
      reset_i      => cnt_reset,
      enable_i     => '1',
      wraparound_o => valid
    );

  proc_debounce : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        cnt_reset <= '1';
        data_reg  <= (others => '0');
        data_o    <= g_RESET_VAL;
      else
        cnt_reset <= '0';
        data_reg  <= data_i;
        -- if data changes reset_counter
        if (data_i /= data_reg) then
          cnt_reset <= '1';
        elsif (valid) then
          -- if counter expired, set output
          data_o <= data_i;
        end if;
      end if;
    end if;

  end process proc_debounce;

end architecture rtl;
