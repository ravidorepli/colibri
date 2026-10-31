--! @title  AXI Stream to Avalon ST adapter
--! @file axis_to_avst.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 06-03-2024
--! @version 0.1

--! This module converts an AXI Stream Interface to Avalon ST interface.
--!
--! It is expected the AXI-Stream byte order is Little-Endian (first byte is
--! at the lower bits) and, in case of partially empty words, the valid bytes
--! are grouped at the lower end.
--!
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

entity axis_to_avst is
  generic (
    g_DATA_WIDTH      : positive := 32;
    --! Avalon-Stream byte order. (AXI-Stream is LITTLE by spec.)
    g_AVST_ENDIANNESS : endian_t := BIG;
    --! TODO: implement skid buffer
    g_ADD_REGISTERS   : boolean  := true
  );
  port (
    clk_i   : in    std_logic;
    reset_i : in    std_logic;

    --! @virtualbus AXI Stream @dir in sink
    snk_tready_o : out   std_logic;
    snk_tvalid_i : in    std_logic;
    snk_tlast_i  : in    std_logic;
    snk_tkeep_i  : in    std_logic_vector((g_DATA_WIDTH / 8) - 1 downto 0);
    snk_tdata_i  : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    --! @end
    --! @virtualbus Avalon-ST @dir out source
    src_ready_i  : in    std_logic;
    src_valid_o  : out   std_logic;
    src_sop_o    : out   std_logic;
    src_eop_o    : out   std_logic;
    src_empty_o  : out   unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);
    src_data_o   : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0)
  --! @end
  );
end entity axis_to_avst;

architecture rtl of axis_to_avst is

  signal last_eop : std_logic;

  function keep_to_empty (keep : std_logic_vector) return unsigned is

    variable v_empty  : unsigned(log2ceil(keep'length) - 1 downto 0);
    variable v_onehot : std_logic_vector(keep'range);

  begin

    assert keep /= (keep'range => '0')
      report "keep cannot be 0"
      severity failure;

    v_onehot := keep xor ('0' & keep(keep'left downto 1));

    for i in v_onehot'range loop

      if (v_onehot(i) = '1') then
        v_empty := to_unsigned(keep'length - 1 - i, v_empty'length);
      end if;

    end loop;

    return v_empty;

  end function keep_to_empty;

begin

  gen_endianness_data : if g_AVST_ENDIANNESS = BIG generate
    src_data_o <= swap_endianness(snk_tdata_i);
  else generate
    src_data_o <= snk_tdata_i;
  end generate gen_endianness_data;

  src_eop_o    <= snk_tlast_i;
  src_valid_o  <= snk_tvalid_i;
  snk_tready_o <= src_ready_i;

  src_empty_o <= keep_to_empty(snk_tkeep_i) when snk_tlast_i = '1' else
                 (others => '0');

  src_sop_o <= '1' when last_eop = '1' and snk_tvalid_i = '1' else
               '0';

  proc_sop_driver : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        last_eop <= '1';
      else
        if (snk_tvalid_i = '1' and snk_tready_o = '1') then
          last_eop <= snk_tlast_i;
        end if;
      end if;
    end if;

  end process proc_sop_driver;

end architecture rtl;
