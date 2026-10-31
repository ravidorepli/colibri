--! @title edge_detect
--! @file edge_detect.vhdl
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

entity edge_detect is
  generic (
    g_RESET_VAL : std_logic := '0'
  );
  port (
    clk_i   : in    std_logic;
    data_i  : in    std_logic;
    pulse_o : out   std_logic
  );
end entity edge_detect;

architecture rtl of edge_detect is

  signal data_reg : std_logic;

begin

  proc_reg : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      data_reg <= data_i;
    end if;

  end process proc_reg;

  pulse_o <= data_i when data_i /= data_reg and data_i /= g_RESET_VAL else
             g_RESET_VAL;

end architecture rtl;
