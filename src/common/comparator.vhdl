--==================================================================================================
--! @brief Simple Comparator
--! @file comparator.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 26-09-2025 Created
--! @version 0.1
--! @copyright CERN 2025
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

--==================================================================================================
--! @brief Simple Comparator
--! @details
--! Comparator component that outputs a signal when the a is greater than b.
--! The comparator is activated only when the enable is high.
--! the g_IS_EQUAL Generic changes the behavior by doing a greater or equal comparison.
--! The trigger has a delay of 1 cycle (single register).
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity comparator is
  generic (
    g_DATA_WIDTH : positive := 32;
    g_IS_EQUAL   : boolean  := false
  );
  port (
    clk_i    : in    std_logic;
    -- inputs
    enable_i : in    std_logic;
    a_i      : in    unsigned(g_DATA_WIDTH - 1 downto 0);
    b_i      : in    unsigned(g_DATA_WIDTH - 1 downto 0);
    -- outputs
    a_gt_b_o : out   std_logic
  );
end entity comparator;

architecture rtl of comparator is

begin

  proc_main : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      a_gt_b_o <= '0';
      if (enable_i = '1') then
        if ((a_i > b_i and not g_IS_EQUAL) or
            (a_i >= b_i and g_IS_EQUAL)) then
          a_gt_b_o <= '1';
        end if;
      end if;
    end if;

  end process proc_main;

end architecture rtl;
