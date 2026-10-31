--! @file simple_dpram.vhdl
--! @brief Simple Dual-Port RAM
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 04-03-2024 Created
--! @version 0.4
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
--! @brief Simple Dual-Port RAM
--! @details
--!
--!  This RAM component features separate read and write ports, with separate
--!  clocks.
--!  The ports can be configured with different widths, which could be supported by hardware.
--!  Please check with the vendor which combination of widths is allowed for the ram primitives.
--!
--!  It is designed to be able to synthesize as BRAM.
--!
--!  Changelog:
--!    - 0.4 separate optimized versions
--!    - 0.3 rewrite write and read ops because vivado is not able to synthesize the ram.
--!    - 0.2 adds support for mixed width ports.
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity simple_dpram is
  generic (
    --! RAM width in bits (legacy behaviour)
    g_DATA_WIDTH   : positive := 16;
    --! RAM port A width in bits (by default set to g_DATA_WIDTH)
    g_A_DATA_WIDTH : positive := g_DATA_WIDTH;
    --! RAM port B width in bits (modify to infer mixed width RAM)
    g_B_DATA_WIDTH : positive := g_A_DATA_WIDTH;
    --! RAM depth as number of data words of the largest port size
    g_N_WORDS      : positive := 10;
    --! RAM address A port
    g_A_ADDR_WIDTH : positive := log2ceil(max_int(g_A_DATA_WIDTH, g_B_DATA_WIDTH) * g_N_WORDS / g_A_DATA_WIDTH);
    --! RAM address B port
    g_B_ADDR_WIDTH : positive := log2ceil(max_int(g_A_DATA_WIDTH, g_B_DATA_WIDTH) * g_N_WORDS / g_B_DATA_WIDTH);
    --! Add output register to ease timing
    g_REGISTER_OUT : boolean  := false;

    --! initialization file
    g_INIT_FILE  : string                                        := "";
    --! Initial value to fill the RAM with (in case no init. file is specified)
    g_INIT_WORD  : std_logic_vector(g_A_DATA_WIDTH - 1 downto 0) := (others => '0');
    --! implementation style, use VIVADO or QUARTUS to force a specific implementation
    g_IMPL_STYLE : compiler_t                                    := get_compiler
  );
  port (
    --! Write port
    wrclk_i  : in    std_logic;                                     --! Clock
    wren_i   : in    std_logic;                                     --! Write enable
    wraddr_i : in    unsigned(g_A_ADDR_WIDTH - 1 downto 0);         --! Address
    wrdata_i : in    std_logic_vector(g_A_DATA_WIDTH - 1 downto 0); --! Data input

    --! Read port
    rdclk_i  : in    std_logic;                                    --! Clock
    rden_i   : in    std_logic;                                    --! Read enable
    rdaddr_i : in    unsigned(g_B_ADDR_WIDTH - 1 downto 0);        --! Address
    rddata_o : out   std_logic_vector(g_B_DATA_WIDTH - 1 downto 0) --! Data output
  );
end entity simple_dpram;

----------------------------------------------------------------------------------------------------

architecture rtl of simple_dpram is

  --! internal memory width
  constant c_MEM_WIDTH  : positive := min_int(g_A_DATA_WIDTH, g_B_DATA_WIDTH);
  --! port ratio
  constant c_PORT_RATIO : positive := max_int(g_A_DATA_WIDTH, g_B_DATA_WIDTH) / c_MEM_WIDTH;
  --! internal memory depth
  constant c_MEM_DEPTH  : positive := g_N_WORDS * c_PORT_RATIO;
  --! Ratio between B port and memory
  constant c_A_RATIO    : positive := g_A_DATA_WIDTH / c_MEM_WIDTH;
  --! Ratio between B port and memory
  constant c_B_RATIO    : positive := g_B_DATA_WIDTH / c_MEM_WIDTH;

  signal read_b : std_logic_vector(rddata_o'range);

begin ----------------------------------------------------------------------------------------------

  gen_impl_style : if g_IMPL_STYLE = QUARTUS generate
  begin

    simple_dpram_altera_inst : entity work.simple_dpram_altera
      generic map (
        g_DATA_WIDTH   => g_DATA_WIDTH,
        g_A_DATA_WIDTH => g_A_DATA_WIDTH,
        g_B_DATA_WIDTH => g_B_DATA_WIDTH,
        g_N_WORDS      => g_N_WORDS,
        g_A_ADDR_WIDTH => g_A_ADDR_WIDTH,
        g_B_ADDR_WIDTH => g_B_ADDR_WIDTH,
        g_REGISTER_OUT => g_REGISTER_OUT
      )
      port map (
        wrclk_i  => wrclk_i,
        wren_i   => wren_i,
        wraddr_i => wraddr_i,
        wrdata_i => wrdata_i,
        rdclk_i  => rdclk_i,
        rden_i   => rden_i,
        rdaddr_i => rdaddr_i,
        rddata_o => rddata_o
      );

  else generate

    simple_dpram_xilinx_inst : entity work.simple_dpram_xilinx
      generic map (
        g_DATA_WIDTH   => g_DATA_WIDTH,
        g_A_DATA_WIDTH => g_A_DATA_WIDTH,
        g_B_DATA_WIDTH => g_B_DATA_WIDTH,
        g_N_WORDS      => g_N_WORDS,
        g_A_ADDR_WIDTH => g_A_ADDR_WIDTH,
        g_B_ADDR_WIDTH => g_B_ADDR_WIDTH,
        g_REGISTER_OUT => g_REGISTER_OUT,
        g_INIT_FILE    => g_INIT_FILE,
        g_INIT_WORD    => g_INIT_WORD
      )
      port map (
        wrclk_i  => wrclk_i,
        wren_i   => wren_i,
        wraddr_i => wraddr_i,
        wrdata_i => wrdata_i,
        rdclk_i  => rdclk_i,
        rden_i   => rden_i,
        rdaddr_i => rdaddr_i,
        rddata_o => rddata_o
      );

  end generate gen_impl_style;

end architecture rtl;

----------------------------------------------------------------------------------------------------
