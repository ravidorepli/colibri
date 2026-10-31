--==================================================================================================
--! @brief 8b/10b Encoder
--! @file encode_8b10b.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 19-11-2025 Created
--! @version 0.2
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.types.all;
  use colibri.common_8b10b.all;

--==================================================================================================
--! @brief 8b/10b Encoder
--! @details lookup table (ROM)-based 8b/10b encoder.
--! The lookup table approach guarantees minimal resource usage and short combinatorial paths.
--!
--! Changelog:
--! - 0.2 reformatted for Vivado to infer primitives
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity encode_8b10b is
  port (
    clk_i         : in    std_logic;
    -- input
    snk_data_i    : in    std_logic_vector(7 downto 0);
    snk_valid_i   : in    std_logic;
    snk_control_i : in    std_logic; --! inject K code
    -- output
    src_data_o    : out   std_logic_vector(9 downto 0);
    src_valid_o   : out   std_logic
  );
end entity encode_8b10b;

architecture rtl of encode_8b10b is

  signal reg_enc      : std_logic_vector(10 downto 0);
  signal reg_valid    : std_logic := '0';
  signal reg_rd       : std_logic := '0';
  -- encoding ROM: declaration required for vivado to infer ROM primitives
  signal encoding_rom : slv_array_t(0 to 1023)(10 downto 0) := c_ENCODE_ROM_8B10B;

begin

  -- two stage architecture
  proc_main : process (clk_i) is

    variable v_addr : std_logic_vector(9 downto 0);

  begin

    if rising_edge(clk_i) then
      reg_valid <= snk_valid_i;
      -- 1. read from rom and register
      if (snk_valid_i) then
        v_addr  := reg_rd & snk_control_i & snk_data_i;
        reg_enc <= encoding_rom(to_integer(unsigned(v_addr)));
      end if;
      -- 2. decode and drive output
      if (reg_valid) then
        src_data_o <= reg_enc(10 downto 1);
        if reg_enc(0) then
          reg_rd <= not reg_rd;
        end if;
        src_valid_o <= not (and(reg_enc));
      else
        src_valid_o <= '0';
      end if;
    end if;

  end process proc_main;

end architecture rtl;
