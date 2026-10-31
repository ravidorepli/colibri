--! @title Avalon ST to AXI Stream adapter
--! @file avst_to_axis.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 04-03-2024
--! @version 0.1

--! This module converts Avalon ST interface to an AXI Stream Interface.
--! Release log:
--! - 0.1 first release
--! - 0.2 changed g_SWAP_ENDIANNESS for g_AVST_ENDIANNESS
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;

entity avst_to_axis is
  generic (
    g_DATA_WIDTH      : positive := 32;
    --! Avalon-Stream byte order. (AXI-Stream is LITTLE by spec.)
    g_AVST_ENDIANNESS : endian_t := BIG;
    --! TODO: implement skid buffer
    g_ADD_REGISTERS   : boolean  := true
  );
  port (
    clk_i        : in    std_logic;
    reset_i      : in    std_logic;
    --! @virtualbus Avalon-ST @dir in sink
    snk_ready_o  : out   std_logic;
    snk_valid_i  : in    std_logic;
    snk_sop_i    : in    std_logic;
    snk_eop_i    : in    std_logic;
    snk_empty_i  : in    unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);
    snk_data_i   : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    --! @end
    --! @virtualbus AXI Stream @dir out source
    src_tready_i : in    std_logic;
    src_tvalid_o : out   std_logic;
    src_tlast_o  : out   std_logic;
    src_tkeep_o  : out   std_logic_vector((g_DATA_WIDTH / 8) - 1 downto 0);
    src_tdata_o  : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0)
  --! @end
  );
end entity avst_to_axis;

architecture rtl of avst_to_axis is

  impure function empty_to_keep (
    empty : snk_empty_i'subtype
  ) return src_tkeep_o'subtype is

    variable v_tkeep : src_tkeep_o'subtype;

  begin

    for i in v_tkeep'range loop

      if (i < v_tkeep'length - to_integer(empty)) then
        v_tkeep(i) := '1';
      else
        v_tkeep(i) := '0';
      end if;

    end loop;

    return v_tkeep;

  end function empty_to_keep;

begin

  gen_endianness_data : if g_AVST_ENDIANNESS = BIG generate
    src_tdata_o <= swap_endianness(snk_data_i);
  else generate
    src_tdata_o <= snk_data_i;
  end generate gen_endianness_data;

  src_tlast_o  <= snk_eop_i;
  src_tvalid_o <= snk_valid_i;
  snk_ready_o  <= src_tready_i;

  src_tkeep_o <= empty_to_keep(snk_empty_i)
                 when snk_eop_i = '1' and snk_empty_i /= (snk_empty_i'range => '0') else
                 (others => '1');

end architecture rtl;
