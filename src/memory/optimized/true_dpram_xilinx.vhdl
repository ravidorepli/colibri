--! @file true_dpram_xilinx.vhdl
--! @brief Xilinx-style True Dual-Port RAM
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 13-03-2026 Created
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
--! @brief Xilinx-style True Dual-Port RAM with mixed width support
--! @details
--!
--!  This RAM component features 2 independent read/write ports in separate
--!  clock domains.
--!  The ports can be configured with different widths, which could be supported by hardware.
--!  Please check with the vendor which combination of widths is allowed for the ram primitives.
--!  It is designed to be able to synthesize as BRAM.
--!  Changelog:
--!    - 0.1 moved generic entity to xilinx style

-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity true_dpram_xilinx is
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
    --! Select write/read-first port operation
    g_WRITE_FIRST  : boolean  := true;
    --! Add output register to ease timing
    g_REGISTER_OUT : boolean  := false;

    --! initialization file
    g_INIT_FILE : string                                      := "";
    --! Initial value to fill the RAM with (in case no init. file is specified)
    g_INIT_WORD : std_logic_vector(g_DATA_WIDTH - 1 downto 0) := (others => '0')
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
end entity true_dpram_xilinx;

----------------------------------------------------------------------------------------------------

architecture rtl of true_dpram_xilinx is

  --! internal v_memory width
  constant c_MEM_WIDTH  : positive := minimum(g_A_DATA_WIDTH, g_B_DATA_WIDTH);
  --! port ratio
  constant c_PORT_RATIO : positive := maximum(g_A_DATA_WIDTH, g_B_DATA_WIDTH) / c_MEM_WIDTH;
  --! internal v_memory depth
  constant c_MEM_DEPTH  : positive := g_N_WORDS * c_PORT_RATIO;
  --! Ratio between B port and v_memory
  constant c_A_RATIO    : positive := g_A_DATA_WIDTH / c_MEM_WIDTH;
  --! Ratio between B port and v_memory
  constant c_B_RATIO    : positive := g_B_DATA_WIDTH / c_MEM_WIDTH;

  signal read_a : dataa_o'subtype;
  signal read_b : datab_o'subtype;

  shared variable v_memory : slv_array_t(0 to c_MEM_DEPTH - 1)(c_MEM_WIDTH - 1 downto 0) :=
                  init_mem_hex(g_INIT_FILE, c_MEM_WIDTH, c_MEM_DEPTH, g_INIT_WORD);

begin ----------------------------------------------------------------------------------------------

  gen_a_wider : if g_A_DATA_WIDTH > g_B_DATA_WIDTH generate

    proc_port_a_mux : process (clka_i) is

      variable v_ptr : integer range 0 to c_MEM_DEPTH - 1;

    begin

      if rising_edge(clka_i) then
        if (g_WRITE_FIRST) then
          if (wra_i = '1') then

            for i in 0 to c_A_RATIO - 1 loop
              v_ptr           := to_integer(addra_i & to_unsigned(i, log2ceil(c_A_RATIO)));
              v_memory(v_ptr) :=
                dataa_i(dataa_i'left - (i * c_MEM_WIDTH) downto
                        (dataa_i'length - (i + 1) * c_MEM_WIDTH));
            end loop;

            read_a <= dataa_i;
          else

            for i in 0 to c_A_RATIO - 1 loop
              v_ptr                                    := to_integer(addra_i & to_unsigned(i, log2ceil(c_A_RATIO)));
              read_a(read_a'left - (i * c_MEM_WIDTH) downto
              (read_a'length - (i + 1) * c_MEM_WIDTH)) <= v_memory(v_ptr);
            end loop;

          end if;
        else

          for i in 0 to c_A_RATIO - 1 loop
            v_ptr                                    := to_integer(addra_i & to_unsigned(i, log2ceil(c_A_RATIO)));
            read_a(read_a'left - (i * c_MEM_WIDTH) downto
            (read_a'length - (i + 1) * c_MEM_WIDTH)) <= v_memory(v_ptr);
            if (wra_i = '1') then
              v_memory(v_ptr) :=
                dataa_i(dataa_i'left - (i * c_MEM_WIDTH) downto
                        (dataa_i'length - (i + 1) * c_MEM_WIDTH));
            end if;
          end loop;

        end if;
      end if;

    end process proc_port_a_mux;

  else generate

    proc_port_a_direct : process (clka_i) is
    begin

      if rising_edge(clka_i) then
        if (g_WRITE_FIRST) then
          if (wra_i = '1') then
            v_memory(to_integer(addra_i)) := dataa_i;
            read_a                        <= dataa_i;
          else
            read_a <= v_memory(to_integer(addra_i));
          end if;
        else
          read_a <= v_memory(to_integer(addra_i));
          if (wra_i = '1') then
            v_memory(to_integer(addra_i)) := dataa_i;
          end if;
        end if;
      end if;

    end process proc_port_a_direct;

  end generate gen_a_wider;

  gen_b_wider : if g_B_DATA_WIDTH > g_A_DATA_WIDTH generate

    proc_port_b_mux : process (clkb_i) is

      variable v_ptr : integer range 0 to c_MEM_DEPTH - 1;

    begin

      if rising_edge(clkb_i) then
        if (g_WRITE_FIRST) then
          if (wrb_i = '1') then

            for i in 0 to c_B_RATIO - 1 loop
              v_ptr           := to_integer(addrb_i & to_unsigned(i, log2ceil(c_B_RATIO)));
              v_memory(v_ptr) :=
                datab_i(datab_i'left - (i * c_MEM_WIDTH) downto
                        (datab_i'length - (i + 1) * c_MEM_WIDTH));
            end loop;

            read_b <= datab_i;
          else

            for i in 0 to c_B_RATIO - 1 loop
              v_ptr                                    := to_integer(addrb_i & to_unsigned(i, log2ceil(c_B_RATIO)));
              read_b(read_b'left - (i * c_MEM_WIDTH) downto
              (read_b'length - (i + 1) * c_MEM_WIDTH)) <= v_memory(v_ptr);
            end loop;

          end if;
        else

          for i in 0 to c_B_RATIO - 1 loop
            v_ptr                                    := to_integer(addrb_i & to_unsigned(i, log2ceil(c_B_RATIO)));
            read_b(read_b'left - (i * c_MEM_WIDTH) downto
            (read_b'length - (i + 1) * c_MEM_WIDTH)) <= v_memory(v_ptr);
            if (wrb_i) then
              v_memory(v_ptr) :=
                datab_i(datab_i'left - (i * c_MEM_WIDTH) downto
                        (datab_i'length - (i + 1) * c_MEM_WIDTH));
            end if;
          end loop;

        end if;
      end if;

    end process proc_port_b_mux;

  else generate

    proc_port_b_direct : process (clkb_i) is
    begin

      if rising_edge(clkb_i) then
        if (g_WRITE_FIRST) then
          if (wrb_i = '1') then
            v_memory(to_integer(addrb_i)) := datab_i;
            read_b                        <= datab_i;
          else
            read_b <= v_memory(to_integer(addrb_i));
          end if;
        else
          read_b <= v_memory(to_integer(addrb_i));
          if (wrb_i = '1') then
            v_memory(to_integer(addrb_i)) := datab_i;
          end if;
        end if;
      end if;

    end process proc_port_b_direct;

  end generate gen_b_wider;

  dataa_o <= read_a when registered(clka_i, g_REGISTER_OUT);
  datab_o <= read_b when registered(clkb_i, g_REGISTER_OUT);

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
