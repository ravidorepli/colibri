--! @file rom.vhdl
--! @brief Read-Only Memory
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 27-06-2025 Created
--! @version 0.1
--! @copyright CERN 2025
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;
  use colibri.mem.all;

--==================================================================================================
--! @brief Read-Only Memory
--! @details
--!
--!  The ROM contents are initialized from a text file, by setting its path to
--!  the `g_INIT_FILE` generic parameter. The file should contain one word per
--!  line (e.g. `g_N_WORDS` lines) in hexadecimal format.
--!
--!  Words are read from ROM by setting the appropriate address at the `addr_i`
--!  port. The data will be available on the `data_o` port on the next clock
--!  cycle.
--!
--!  This component is designed to be able to synthesize as BRAM.
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity rom is
  generic (
    --! Number of words to store
    g_N_WORDS    : positive;
    --! Word size in bits
    g_DATA_WIDTH : positive;
    --! Initialization file path
    g_INIT_FILE  : string := ""
  );
  port (
    --! Clock
    clk_i : in    std_logic;

    --! Read address and data
    addr_i : in    unsigned(log2ceil(g_N_WORDS) - 1 downto 0);
    data_o : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0)
  );
end entity rom;

----------------------------------------------------------------------------------------------------

architecture rtl of rom is

  signal memory : slv_array_t(0 to g_N_WORDS - 1)(g_DATA_WIDTH - 1 downto 0) :=
         init_mem_hex(g_INIT_FILE, g_DATA_WIDTH, g_N_WORDS, std_logic_vector(to_unsigned(0, g_DATA_WIDTH)));

begin ----------------------------------------------------------------------------------------------

  proc_read : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      data_o <= memory(to_integer(addr_i));
    end if;

  end process proc_read;

end architecture rtl;

----------------------------------------------------------------------------------------------------
