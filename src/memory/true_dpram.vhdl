--! @file true_dpram.vhdl
--! @brief True Dual-Port RAM
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 04-03-2024 Created
--! @version 0.5
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
--! @brief True Dual-Port RAM with mixed width support
--! @details
--!
--!  This RAM component features 2 independent read/write ports in separate
--!  clock domains.
--!  The ports can be configured with different widths, which could be supported by hardware.
--!  Please check with the vendor which combination of widths is allowed for the ram primitives.
--!  It is designed to be able to synthesize as BRAM.
--!  Changelog:
--!    - 0.5 separate optimized versions
--!    - 0.4 remove write and read procedure because vivado is not able to synthesize the ram.
--!    - 0.3 adds support for mixed width ports.
--!    - 0.2 (mvodnik) Updated for BRAM synth. and added `g_WRITE_FIRST`
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity true_dpram is
  generic (
    --! RAM width in bits
    g_DATA_WIDTH   : positive := 16;
    --! RAM port A width in bits (by default set to g_DATA_WIDTH)
    g_A_DATA_WIDTH : positive := g_DATA_WIDTH;
    --! RAM port B width in bits (modify to infer mixed width RAM)
    g_B_DATA_WIDTH : positive := g_A_DATA_WIDTH;
    --! RAM depth as number of data words of the largest port size
    g_N_WORDS      : positive := 10;
    --! RAM address A port
    g_A_ADDR_WIDTH : positive := log2ceil(maximum(g_A_DATA_WIDTH, g_B_DATA_WIDTH) * g_N_WORDS / g_A_DATA_WIDTH);
    --! RAM address B port
    g_B_ADDR_WIDTH : positive := log2ceil(maximum(g_A_DATA_WIDTH, g_B_DATA_WIDTH) * g_N_WORDS / g_B_DATA_WIDTH);
    --! Select write/read-first port operation (Note: Intel only supports write-first)
    g_WRITE_FIRST  : boolean  := false;
    --! Add output register to ease timing
    g_REGISTER_OUT : boolean  := false;

    --! initialization file
    g_INIT_FILE  : string                                      := "";
    --! Initial value to fill the RAM with (in case no init. file is specified)
    g_INIT_WORD  : std_logic_vector(g_DATA_WIDTH - 1 downto 0) := (others => '0');
    --! Implementation style
    g_IMPL_STYLE : compiler_t                                  := get_compiler
  );
  port (
    --! Port A
    clka_i  : in    std_logic;                                     --! Clock A
    wra_i   : in    std_logic;                                     --! Write enable
    addra_i : in    unsigned(g_A_ADDR_WIDTH - 1 downto 0);         --! Address
    dataa_i : in    std_logic_vector(g_A_DATA_WIDTH - 1 downto 0); --! Data input
    dataa_o : out   std_logic_vector(g_A_DATA_WIDTH - 1 downto 0); --! Data output

    --! Port B
    clkb_i  : in    std_logic;                                     --! Clock B
    wrb_i   : in    std_logic;                                     --! Write enable
    addrb_i : in    unsigned(g_B_ADDR_WIDTH - 1 downto 0);         --! Address
    datab_i : in    std_logic_vector(g_B_DATA_WIDTH - 1 downto 0); --! Data input
    datab_o : out   std_logic_vector(g_B_DATA_WIDTH - 1 downto 0)  --! Data output
  );
end entity true_dpram;

----------------------------------------------------------------------------------------------------

architecture rtl of true_dpram is

begin ----------------------------------------------------------------------------------------------

  gen_impl : if g_IMPL_STYLE = QUARTUS generate
  begin
    -- use altera-style implementation
    true_dpram_altera_inst : entity work.true_dpram_altera
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
        clka_i  => clka_i,
        wra_i   => wra_i,
        addra_i => addra_i,
        dataa_i => dataa_i,
        dataa_o => dataa_o,
        clkb_i  => clkb_i,
        wrb_i   => wrb_i,
        addrb_i => addrb_i,
        datab_i => datab_i,
        datab_o => datab_o
      );

  else generate
    -- use xilinx-style as generic style
    true_dpram_xilinx_inst : entity work.true_dpram_xilinx
      generic map (
        g_DATA_WIDTH   => g_DATA_WIDTH,
        g_A_DATA_WIDTH => g_A_DATA_WIDTH,
        g_B_DATA_WIDTH => g_B_DATA_WIDTH,
        g_N_WORDS      => g_N_WORDS,
        g_A_ADDR_WIDTH => g_A_ADDR_WIDTH,
        g_B_ADDR_WIDTH => g_B_ADDR_WIDTH,
        g_WRITE_FIRST  => g_WRITE_FIRST,
        g_REGISTER_OUT => g_REGISTER_OUT,
        g_INIT_FILE    => g_INIT_FILE,
        g_INIT_WORD    => g_INIT_WORD
      )
      port map (
        clka_i  => clka_i,
        wra_i   => wra_i,
        addra_i => addra_i,
        dataa_i => dataa_i,
        dataa_o => dataa_o,
        clkb_i  => clkb_i,
        wrb_i   => wrb_i,
        addrb_i => addrb_i,
        datab_i => datab_i,
        datab_o => datab_o
      );

  end generate gen_impl;

end architecture rtl;

----------------------------------------------------------------------------------------------------
