--==================================================================================================
--! @brief Clock Domain Boundary Synchronizer (Legacy Version)
--!
--!  Synchronizes a generic size std_logic_vector over a clock domain boundary.
--!  Number of register stages is configurable.
--!
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 09-04-2025 Created
--! @version 0.1
--! @copyright CERN 2025
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;

----------------------------------------------------------------------------------------------------

entity synchro is
  generic (
    --! Slv data length
    g_DATA_LENGTH : positive range 1 to natural'high;
    --! Initial values for the output data
    --! (one bit = every bit; unconstrained: Quartus Lite / Standard reject a generic typed by
    --! another generic)
    g_INIT_VALUE  : std_logic_vector := "0";

    --! Number of register stages (must be at least 2)
    g_NUM_STAGES : natural range 2 to natural'high := 2
  );
  port (
    --! Destination clock and reset
    clk_i   : in    std_logic;
    reset_i : in    std_logic;

    --! Source data
    data_i : in    std_logic_vector(g_DATA_LENGTH - 1 downto 0);
    --! Destination data
    data_o : out   std_logic_vector(g_DATA_LENGTH - 1 downto 0)
  );
end entity synchro;

----------------------------------------------------------------------------------------------------

architecture rtl of synchro is

  subtype data_t is std_logic_vector(g_DATA_LENGTH - 1 downto 0);

  type sync_t is array (0 to g_NUM_STAGES - 1) of data_t;

  -- Synchronization chain of registers
  constant c_INIT_VALUE : data_t := fit_init(g_INIT_VALUE, g_DATA_LENGTH);

  signal sync_chain : sync_t := (others => c_INIT_VALUE);

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
  data_o <= sync_chain(g_NUM_STAGES - 1);

  -- Synchronous process: shifts the register chain every destination clock cycle
  proc_sync : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        sync_chain <= (others => c_INIT_VALUE);
      else
        sync_chain(0) <= data_i;

        for i in 0 to g_NUM_STAGES - 2 loop
          sync_chain(i + 1) <= sync_chain(i);
        end loop;

      end if;
    end if;

  end process proc_sync;

end architecture rtl;

----------------------------------------------------------------------------------------------------
