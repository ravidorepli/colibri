-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;

entity utils_fv is
  port (
    clk_i        : in    std_logic;
    reset_i      : in    std_logic;
    count_ones_i : in    std_logic_vector(63 downto 0);
    count_ones_o : out   natural
  );
end entity utils_fv;

architecture rtl of utils_fv is

begin

  proc_main_clk : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i) then
        null;
      end if;
    end if;

  end process proc_main_clk;

  proc_main_cmb : process (all) is
  begin

    count_ones_o <= count_ones(count_ones_i);

  end process proc_main_cmb;

end architecture rtl;
