--==================================================================================================
--! @brief 8b/10b Decoder
--! @file decode_8b10b.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 19-11-2025 Created
--! @version 0.2
--! @copyright CERN 2025
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.types.all;
  use colibri.common_8b10b.all;

--==================================================================================================
--! @brief 8b/10b Decoder
--! @details lookup table (ROM)-based 8b/10b decoder.
--! The lookup table approach guarantees minimal resource usage and short combinatorial paths.

--! Changelog:
--! - 0.2 reformatted for Vivado to infer primitives
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity decode_8b10b is
  port (
    clk_i         : in    std_logic;
    -- input
    snk_data_i    : in    std_logic_vector(9 downto 0);
    snk_valid_i   : in    std_logic;
    -- output
    src_data_o    : out   std_logic_vector(7 downto 0);
    src_control_o : out   std_logic; --! is K code
    src_valid_o   : out   std_logic
  );
end entity decode_8b10b;

architecture rtl of decode_8b10b is

  signal reg_dec   : std_logic_vector(9 downto 0);
  signal reg_valid : std_logic := '0';
  signal reg_rd    : std_logic := '0';

  -- decoding ROM: declaration required for vivado to infer ROM primitives
  signal decoding_rom : slv_array_t(0 to 1023)(9 downto 0) := c_DECODE_ROM_8B10B;

begin

  -- two stage architecture
  proc_main : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      reg_valid <= snk_valid_i;
      -- 1. read from rom and register
      if (snk_valid_i) then
        reg_dec <= decoding_rom(to_integer(unsigned(snk_data_i)));
      end if;
      -- 2. decode and drive output
      if (reg_valid) then
        src_data_o    <= reg_dec(9 downto 2);
        src_control_o <= reg_dec(0);
        if reg_dec(1) then
          reg_rd <= not reg_rd;
        end if;
        src_valid_o <= not (and(reg_dec));
      else
        src_valid_o <= '0';
      end if;
    end if;

  end process proc_main;

end architecture rtl;
