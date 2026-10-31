-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;

entity debouncer_fv is
  port (
    clk_i   : in    std_logic;
    reset_i : in    std_logic;
    data_i  : in    std_logic_vector(3 downto 0);
    data_o  : out   std_logic_vector(3 downto 0)
  );
end entity debouncer_fv;

architecture rtl of debouncer_fv is

begin

  debouncer_inst : entity colibri.debouncer
    generic map (
      g_RESET_VAL     => (3 downto 0 => '0'),
      g_DEBOUNCE_TIME => 100 ns,
      g_CLOCK_PERIOD  => 10 ns
    )
    port map (
      clk_i   => clk_i,
      reset_i => reset_i,
      data_i  => data_i,
      data_o  => data_o
    );

end architecture rtl;
