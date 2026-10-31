--! @file ram.vhdl
--! @brief Single Port RAM
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 30-11-2023 Created
--! @date 27-06-2025 (mvodnik) Updated for BRAM synth. and added `g_WRITE_FIRST`
--! @version 0.2
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
--! @brief Single Port RAM
--! @details
--!
--!  The contents can be initialized from a text file, by setting its path to
--!  the `g_INIT_FILE` generic parameter. The file should contain one word per
--!  line (e.g. `g_N_WORDS` lines) in hexadecimal format.
--!
--!  This component is designed to be able to synthesize as BRAM.
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity ram is
  generic (
    --! number of words to store in RAM
    g_N_WORDS      : positive;
    --! word size
    g_DATA_WIDTH   : positive;
    --! add registers to write line
    g_REGISTER_IN  : boolean                                     := false;
    --! add register to read line (required for BRAM synthesis)
    g_REGISTER_OUT : boolean                                     := true;
    --! initialization file
    g_INIT_FILE    : string                                      := "";
    --! Initial value to fill the RAM with (in case no init. file is specified)
    g_INIT_WORD    : std_logic_vector(g_DATA_WIDTH - 1 downto 0) := (others => '0');
    --! choose between write- or read-first interface
    g_WRITE_FIRST  : boolean                                     := true
  );
  port (
    clk_i   : in    std_logic;                                   --! clock
    reset_i : in    std_logic;                                   --! reset_i
    addr_i  : in    unsigned(log2ceil(g_N_WORDS) - 1 downto 0);  --! ram address to write to
    we_i    : in    std_logic;                                   --! write request
    data_i  : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0); --! data_i to write
    q_o     : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0)  --! data_i to read
  );
end entity ram;

----------------------------------------------------------------------------------------------------

architecture rtl of ram is

  signal memory : slv_array_t(0 to g_N_WORDS - 1)(g_DATA_WIDTH - 1 downto 0) :=
         init_mem_hex(g_INIT_FILE, g_DATA_WIDTH, g_N_WORDS, g_INIT_WORD);

  -- (Optionally) registered interface signals
  signal reg_addr : natural range 0 to g_N_WORDS - 1;
  signal reg_we   : std_logic;
  signal reg_data : std_logic_vector(g_DATA_WIDTH - 1 downto 0);
  signal reg_q    : std_logic_vector(g_DATA_WIDTH - 1 downto 0);

begin ----------------------------------------------------------------------------------------------

  reg_addr <= to_integer(addr_i) when registered(clk_i, g_REGISTER_IN);
  reg_we   <= we_i when registered(clk_i, g_REGISTER_IN);
  reg_data <= data_i when registered(clk_i, g_REGISTER_IN);

  proc_ram : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reg_we = '1') then
        memory(reg_addr) <= reg_data;
      end if;

      if (g_REGISTER_OUT) then
        if (reset_i = '1') then
          reg_q <= (others => '0');
        else
          if (g_WRITE_FIRST and reg_we = '1') then
            reg_q <= reg_data;
          else
            reg_q <= memory(reg_addr);
          end if;
        end if;
      end if;
    end if;

  end process proc_ram;

  gen_async_read : if g_REGISTER_OUT generate
    q_o <= reg_q;
  else generate
    q_o <= reg_data when g_WRITE_FIRST and reg_we = '1' else
           memory(reg_addr);
  end generate gen_async_read;

end architecture rtl;

----------------------------------------------------------------------------------------------------
