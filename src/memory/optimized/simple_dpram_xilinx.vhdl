--! @file simple_dpram_xilinx.vhdl
--! @brief Xilinx-Style Simple Dual-Port RAM
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
--! @brief Xilinx-Style Simple Dual-Port RAM
--! @details
--!
--!  This RAM component features separate read and write ports, with separate clocks.
--!  The ports can be configured with different widths, which could be supported by hardware.
--!  Please check with the vendor which combination of widths is allowed for the ram primitives.
--!
--!  It is designed to be able to synthesize as BRAM.
--!
--!  Changelog:
--!    - 0.1 Moved from generic `simple_dpram` to xilinx-style.
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity simple_dpram_xilinx is
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
    g_INIT_FILE : string                                        := "";
    --! Initial value to fill the RAM with (in case no init. file is specified)
    g_INIT_WORD : std_logic_vector(g_A_DATA_WIDTH - 1 downto 0) := (others => '0')
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
end entity simple_dpram_xilinx;

----------------------------------------------------------------------------------------------------

architecture rtl of simple_dpram_xilinx is

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

  signal memory : slv_array_t(0 to c_MEM_DEPTH - 1)(c_MEM_WIDTH - 1 downto 0) :=
         init_mem_hex(g_INIT_FILE, c_MEM_WIDTH, c_MEM_DEPTH, g_INIT_WORD);

begin ----------------------------------------------------------------------------------------------

  gen_a_wider : if g_A_DATA_WIDTH > g_B_DATA_WIDTH generate

    proc_write_ram_mux : process (wrclk_i) is

      variable v_ptr : integer range 0 to c_MEM_DEPTH - 1;

    begin

      if rising_edge(wrclk_i) then

        for i in 0 to c_A_RATIO - 1 loop
          if (wren_i = '1') then
            v_ptr         := to_integer(wraddr_i & to_unsigned(i, log2ceil(c_A_RATIO)));
            memory(v_ptr) <=
              wrdata_i(wrdata_i'left - (i * c_MEM_WIDTH) downto
                       (wrdata_i'length - (i + 1) * c_MEM_WIDTH));
          end if;
        end loop;

      end if;

    end process proc_write_ram_mux;

  else generate

    proc_write_ram_direct : process (wrclk_i) is
    begin

      if rising_edge(wrclk_i) then
        if (wren_i = '1') then
          memory(to_integer(wraddr_i)) <= wrdata_i;
        end if;
      end if;

    end process proc_write_ram_direct;

  end generate gen_a_wider;

  gen_b_wider : if g_B_DATA_WIDTH > g_A_DATA_WIDTH generate

    proc_read_ram_mux : process (rdclk_i) is

      variable v_ptr : integer range 0 to c_MEM_DEPTH - 1;

    begin

      if rising_edge(rdclk_i) then

        for i in 0 to c_B_RATIO - 1 loop
          if (rden_i = '1') then
            v_ptr                                    := to_integer(rdaddr_i & to_unsigned(i, log2ceil(c_B_RATIO)));
            read_b(read_b'left - (i * c_MEM_WIDTH) downto
            (read_b'length - (i + 1) * c_MEM_WIDTH)) <= memory(v_ptr);
          end if;
        end loop;

      end if;

    end process proc_read_ram_mux;

  else generate

    proc_read_ram_direct : process (rdclk_i) is
    begin

      if rising_edge(rdclk_i) then
        if (rden_i = '1') then
          read_b <= memory(to_integer(rdaddr_i));
        end if;
      end if;

    end process proc_read_ram_direct;

  end generate gen_b_wider;

  gen_reg_out : if g_REGISTER_OUT generate
    rddata_o <= read_b when rising_edge(rdclk_i);
  else generate
    rddata_o <= read_b;
  end generate gen_reg_out;

  -------------------------------------------------------------------------
  --                             assertions
  -------------------------------------------------------------------------
  assert c_A_RATIO = c_B_RATIO
    report "Implementing a Mixed Width (Asymmetric) dual port RAM. Check FPGA datasheet for allowed widths."
    severity note;

  assert MAXIMUM(g_A_DATA_WIDTH, g_B_DATA_WIDTH) mod MINIMUM(g_A_DATA_WIDTH, g_B_DATA_WIDTH) = 0
    report "Smaller port is not a divisor of larger port. Cannot infer RAM with this configuration."
    severity failure;

  assert g_A_ADDR_WIDTH >= log2ceil(g_N_WORDS / c_A_RATIO)
    report "The Port A Address width is too small to access g_N_WORDS."
    severity failure;

  assert g_B_ADDR_WIDTH >= log2ceil(g_N_WORDS / c_B_RATIO)
    report "The Port B Address width is too small to access g_N_WORDS."
    severity failure;
-------------------------------------------------------------------------

end architecture rtl;

----------------------------------------------------------------------------------------------------
