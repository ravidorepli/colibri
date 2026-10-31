--==================================================================================================
--! @brief Reset signal synchronizer
--!
--!  Synchronizes an asynchronous reset signal to the destination clock domain.
--!
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 15-05-2024 Created
--! @version 0.1
--! @copyright CERN 2024
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

----------------------------------------------------------------------------------------------------

entity synchro_reset is
  generic (
    --! Reset polarities ('1' = active high, '0' = active low)
    g_IN_POLARITY  : std_logic := '1';
    g_OUT_POLARITY : std_logic := '1';

    --! Duration of the output reset signal after the input reset has been released
    --! (in terms of destination clock cycles)
    g_DURATION : positive := 1
  );
  port (
    --! Destination clock
    clk_i : in    std_logic;

    --! Asynchronous reset
    reset_i : in    std_logic;

    --! Destination clock domain synchronous reset
    reset_o : out   std_logic
  );
end entity synchro_reset;

----------------------------------------------------------------------------------------------------

architecture rtl of synchro_reset is

  -- Synchronization chain of registers
  signal sync_chain : std_logic_vector(g_DURATION downto 0) := (others => not g_OUT_POLARITY);

  -- CDC attributes for ALTERA/INTEL
  attribute preserve                       : boolean;
  attribute altera_attribute               : string;
  attribute preserve of sync_chain         : signal is true;
  attribute altera_attribute of sync_chain : signal is
     "-name SYNCHRONIZER_IDENTIFICATION ""FORCED IF ASYNCHRONOUS""";

  -- CDC attributes for XILINX/AMD
  attribute async_reg : boolean;
  attribute dont_touch : boolean;
  attribute async_reg of sync_chain  : signal is TRUE;
  attribute dont_touch of sync_chain : signal is TRUE;

begin

  -- Output the last element of the register chain
  reset_o <= sync_chain(sync_chain'left);

  -- Async. reset + Sync. register chain shifting
  proc_sync : process (clk_i, reset_i) is
  begin

    if (reset_i = g_IN_POLARITY) then
      sync_chain <= (others => g_OUT_POLARITY);
    elsif rising_edge(clk_i) then
      sync_chain <= sync_chain(sync_chain'left - 1 downto 0) & not g_OUT_POLARITY;
    end if;

  end process proc_sync;

end architecture rtl;

----------------------------------------------------------------------------------------------------
