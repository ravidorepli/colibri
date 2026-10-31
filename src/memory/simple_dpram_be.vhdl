--! @file simple_dpram_be.vhdl
--! @brief Simple Dual-Port RAM with write byte-enable
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 06-06-2025 Created
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
--! @brief Simple Dual-Port RAM with write byte-enable
--! @details
--!
--!  This RAM component features separate read and write ports, with separate
--!  clocks.
--!  Additionally, the write port features a byte-enable vector (`wren_i`),
--!  so only a subset of the bytes in the input word may be written.
--!
--!  This component is designed to be able to synthesize as BRAM.
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity simple_dpram_be is
  generic (
    --! Byte width in bits (AMD supports 8, 9, 16 or 18)
    g_BYTE_WIDTH : positive                                                   := 8;
    --! Bytes per data word - RAM width
    g_WORD_BYTES : positive;
    --! Words to store - RAM depth
    g_N_WORDS    : positive;
    --! initialization file
    g_INIT_FILE  : string                                                     := "";
    --! Initial value to fill the RAM with (in case no init. file is specified)
    g_INIT_WORD  : std_logic_vector(g_WORD_BYTES * g_BYTE_WIDTH - 1 downto 0) := (others => '0')
  );
  port (
    --! Write port with byte-enable
    wrclk_i  : in    std_logic;
    wren_i   : in    std_logic_vector(g_WORD_BYTES - 1 downto 0);
    wraddr_i : in    unsigned(log2ceil(g_N_WORDS) - 1 downto 0);
    wrdata_i : in    std_logic_vector(g_WORD_BYTES * g_BYTE_WIDTH - 1 downto 0);

    --! Read port
    rdclk_i  : in    std_logic;
    rden_i   : in    std_logic;
    rdaddr_i : in    unsigned(log2ceil(g_N_WORDS) - 1 downto 0);
    rddata_o : out   std_logic_vector(g_WORD_BYTES * g_BYTE_WIDTH - 1 downto 0)
  );
end entity simple_dpram_be;

----------------------------------------------------------------------------------------------------

architecture rtl of simple_dpram_be is

  signal memory : slv_array_t(0 to g_N_WORDS - 1)(wrdata_i'length - 1 downto 0) :=
         init_mem_hex(g_INIT_FILE, g_WORD_BYTES * g_BYTE_WIDTH, g_N_WORDS, g_INIT_WORD);

begin ----------------------------------------------------------------------------------------------

  ------------------------------------------------------------------------------
  --! Synchronous write port with byte-enable
  ------------------------------------------------------------------------------
  proc_write_ram : process (wrclk_i) is
  begin

    if rising_edge(wrclk_i) then

      for i in wren_i'range loop
        if (wren_i(i) = '1') then
          memory(to_integer(wraddr_i))((i + 1) * g_BYTE_WIDTH - 1 downto i * g_BYTE_WIDTH) <=
            wrdata_i((i + 1) * g_BYTE_WIDTH - 1 downto i * g_BYTE_WIDTH);
        end if;
      end loop;

    end if;

  end process proc_write_ram;

  ------------------------------------------------------------------------------
  --! Synchronous read port
  ------------------------------------------------------------------------------
  proc_read_ram : process (rdclk_i) is
  begin

    if rising_edge(rdclk_i) then
      if (rden_i = '1') then
        rddata_o <= memory(to_integer(rdaddr_i));
      end if;
    end if;

  end process proc_read_ram;

end architecture rtl;

----------------------------------------------------------------------------------------------------
