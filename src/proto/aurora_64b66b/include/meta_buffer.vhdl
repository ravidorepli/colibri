--! @brief Metadata propagation buffer
--! @file meta_buffer.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 16-01-2024
--! @version 0.2
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
--==================================================================================================
--! @brief Metadata propagation buffer
--! @details
--! buffer to propagate metadata in pipelined streams
--! changelog:
--! - 0.1: initial release
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity meta_buffer is
  generic (

    constant g_DATA_WIDTH  : positive := 2 --! word size
  );
  port (
    clk_i       : in    std_logic;
    reset_i     : in    std_logic;
    --! @virtualbus Avalon-ST @dir in
    snk_data_i  : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0); --! data input
    snk_valid_i : in    std_logic;                                   --! input valid signal
    snk_ready_o : out   std_logic;                                   --! ready back pressure propagation
    --! @end
    --! @virtualbus Avalon-ST @dir out
    src_valid_o : out   std_logic;                                   --! valid output signal
    src_ready_i : in    std_logic;                                   --! source ready signal
    src_data_o  : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0)  --! data output
  --! @end
  );
end entity meta_buffer;

architecture rtl of meta_buffer is

  signal tmpo_valid : std_logic;
  signal tmpo_data  : std_logic_vector(snk_data_i'range);
  signal reg_valid  : std_logic;
  signal cmb_valid  : std_logic;
  signal reg_data   : tmpo_data'subtype;
  signal cmb_data   : tmpo_data'subtype;

begin

  snk_ready_o <= src_ready_i;

  proc_reg_copy : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        tmpo_valid <= '0';
        tmpo_data  <= (others => '0');
      else
        tmpo_valid <= snk_valid_i;
        tmpo_data  <= snk_data_i;
      end if;
    end if;

  end process proc_reg_copy;

  proc_register_output : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        reg_valid <= '0';
      else
        if (src_ready_i = '0' and reg_valid = '0') then
          reg_valid <= tmpo_valid;
          reg_data  <= tmpo_data;
        end if;
        if (src_ready_i = '1' and reg_valid = '1') then
          reg_valid <= '0';
        end if;
      end if;
    end if;

  end process proc_register_output;

  src_data_o <= reg_data when reg_valid = '1' else
                tmpo_data;
  cmb_valid  <= tmpo_valid or reg_valid;

  src_valid_o <= cmb_valid;

end architecture rtl;
