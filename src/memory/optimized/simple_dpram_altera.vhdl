--! @file simple_dpram_altera.vhdl
--! @brief Altera-style Simple Dual-Port RAM
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 13-03-2026
--! @version 0.1
--! @copyright CERN 2026
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
--! @brief Altera-Style Simple Dual-Port RAM
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
--!    - 0.1 Moved from `simple_dpram` to an altera-style version
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity simple_dpram_altera is
  generic (
    --! RAM width in bits (legacy behaviour)
    g_DATA_WIDTH   : positive := 16;
    --! RAM port A width in bits (by default set to g_DATA_WIDTH)
    g_A_DATA_WIDTH : natural  := 0;  -- 0: g_DATA_WIDTH
    --! RAM port B width in bits (modify to infer mixed width RAM)
    g_B_DATA_WIDTH : natural  := 0;  -- 0: the port A width
    --! RAM depth as number of data words of the largest port size
    g_N_WORDS      : positive := 10;
    --! RAM address A port
    g_A_ADDR_WIDTH : natural  := 0;  -- 0: derived (mem_pkg dpram_addr_a)
    --! RAM address B port
    g_B_ADDR_WIDTH : natural  := 0;  -- 0: derived (mem_pkg dpram_addr_b)
    --! Add output register to ease timing
    g_REGISTER_OUT : boolean  := false;


    --! initialization file
    g_INIT_FILE : string                                        := "";
    --! Initial value to fill the RAM with (in case no init. file is specified)
    g_INIT_WORD : std_logic_vector := "0"  -- one bit = every bit
  );
  port (
    --! Write port
    wrclk_i  : in    std_logic;                                     --! Clock
    wren_i   : in    std_logic;                                     --! Write enable
    wraddr_i : in    unsigned(dpram_addr_a(g_DATA_WIDTH, g_A_DATA_WIDTH, g_B_DATA_WIDTH, g_N_WORDS, g_A_ADDR_WIDTH) - 1 downto 0);         --! Address
    wrdata_i : in    std_logic_vector(dpram_width_a(g_DATA_WIDTH, g_A_DATA_WIDTH) - 1 downto 0); --! Data input

    --! Read port
    rdclk_i  : in    std_logic;                                    --! Clock
    rden_i   : in    std_logic;                                    --! Read enable
    rdaddr_i : in    unsigned(dpram_addr_b(g_DATA_WIDTH, g_A_DATA_WIDTH, g_B_DATA_WIDTH, g_N_WORDS, g_B_ADDR_WIDTH) - 1 downto 0);        --! Address
    rddata_o : out   std_logic_vector(dpram_width_b(g_DATA_WIDTH, g_A_DATA_WIDTH, g_B_DATA_WIDTH) - 1 downto 0) --! Data output
  );
end entity simple_dpram_altera;

----------------------------------------------------------------------------------------------------

architecture rtl of simple_dpram_altera is

  -- the resolved generics (0 = default, see mem_pkg)
  constant c_A_DATA_WIDTH : positive := dpram_width_a(g_DATA_WIDTH, g_A_DATA_WIDTH);
  constant c_B_DATA_WIDTH : positive := dpram_width_b(g_DATA_WIDTH, g_A_DATA_WIDTH, g_B_DATA_WIDTH);
  constant c_A_ADDR_WIDTH : positive := dpram_addr_a(g_DATA_WIDTH, g_A_DATA_WIDTH, g_B_DATA_WIDTH, g_N_WORDS, g_A_ADDR_WIDTH);
  constant c_B_ADDR_WIDTH : positive := dpram_addr_b(g_DATA_WIDTH, g_A_DATA_WIDTH, g_B_DATA_WIDTH, g_N_WORDS, g_B_ADDR_WIDTH);
  constant c_INIT_WORD    : std_logic_vector(c_A_DATA_WIDTH - 1 downto 0) := fit_init(g_INIT_WORD, c_A_DATA_WIDTH);

  --! internal memory width
  constant c_MEM_WIDTH  : positive := min_int(c_A_DATA_WIDTH, c_B_DATA_WIDTH);
  --! port ratio
  constant c_PORT_RATIO : positive := max_int(c_A_DATA_WIDTH, c_B_DATA_WIDTH) / c_MEM_WIDTH;
  --! internal memory depth
  constant c_MEM_DEPTH  : positive := g_N_WORDS * c_PORT_RATIO;
  --! Ratio between B port and memory
  constant c_A_RATIO    : positive := c_A_DATA_WIDTH / c_MEM_WIDTH;
  --! Ratio between B port and memory
  constant c_B_RATIO    : positive := c_B_DATA_WIDTH / c_MEM_WIDTH;

  signal read_b : std_logic_vector(rddata_o'range);

  signal memory : slv_array_2d_t(0 to g_N_WORDS - 1)(0 to c_PORT_RATIO - 1)(c_MEM_WIDTH - 1 downto 0) := 
  init_mem_hex(g_INIT_FILE,c_MEM_WIDTH,c_PORT_RATIO,g_N_WORDS,c_INIT_WORD);

begin ----------------------------------------------------------------------------------------------

  gen_a_wider : if c_A_DATA_WIDTH > c_B_DATA_WIDTH generate
    signal wword : slv_array_t(0 to c_PORT_RATIO - 1)(c_MEM_WIDTH - 1 downto 0);
  begin
    wword <= slv_to_slv_array(wrdata_i, c_MEM_WIDTH);

    proc_write_ram_mux : process (wrclk_i) is
    begin

      if rising_edge(wrclk_i) then
        if (wren_i = '1') then
          memory(to_integer(wraddr_i)) <= wword;
        end if;
      end if;

    end process proc_write_ram_mux;

  else generate

    proc_write_ram_direct : process (wrclk_i) is
    begin

      if rising_edge(wrclk_i) then
        if (wren_i = '1') then
          memory(to_integer(wraddr_i / c_PORT_RATIO))
          (to_integer(wraddr_i) mod c_PORT_RATIO) <= wrdata_i;
        end if;
      end if;

    end process proc_write_ram_direct;

  end generate gen_a_wider;

  gen_b_wider : if c_B_DATA_WIDTH > c_A_DATA_WIDTH generate
    signal rword : slv_array_t(0 to c_PORT_RATIO - 1)(c_MEM_WIDTH - 1 downto 0);

  begin

    read_b <= slv_array_to_slv(rword, c_MEM_WIDTH);

    proc_read_ram_mux : process (rdclk_i) is
    begin

      if rising_edge(rdclk_i) then
        if (rden_i = '1') then
          rword <= memory(to_integer(rdaddr_i));
        end if;
      end if;

    end process proc_read_ram_mux;

  else generate

    proc_read_ram_direct : process (rdclk_i) is
    begin

      if rising_edge(rdclk_i) then
        if (rden_i = '1') then
          read_b <= memory(to_integer(rdaddr_i) / c_PORT_RATIO)(to_integer(rdaddr_i) mod c_PORT_RATIO);
        end if;
      end if;

    end process proc_read_ram_direct;

  end generate gen_b_wider;

  rddata_o <= read_b when registered(rdclk_i, g_REGISTER_OUT);

  -------------------------------------------------------------------------
  --                             assertions
  -------------------------------------------------------------------------
  assert c_A_RATIO = c_B_RATIO
    report "Implementing a Mixed Width (Asymmetric) dual port RAM. Check FPGA datasheet for allowed widths."
    severity note;

  assert MAXIMUM(c_A_DATA_WIDTH, c_B_DATA_WIDTH) mod MINIMUM(c_A_DATA_WIDTH, c_B_DATA_WIDTH) = 0
    report "Smaller port is not a divisor of larger port. Cannot infer RAM with this configuration."
    severity failure;

  assert c_A_ADDR_WIDTH >= log2ceil(g_N_WORDS / c_A_RATIO)
    report "The Port A Address width is too small to access g_N_WORDS."
    severity failure;

  assert c_B_ADDR_WIDTH >= log2ceil(g_N_WORDS / c_B_RATIO)
    report "The Port B Address width is too small to access g_N_WORDS."
    severity failure;
-------------------------------------------------------------------------

end architecture rtl;

----------------------------------------------------------------------------------------------------
