--==================================================================================================
--! @brief Bit-shift a stream of data
--!
--!  Introduces a bitwise offset in a continuous data stream.
--!  Input data `data_i` is shifted by the offset `offset_i` and presented at
--!  the output `data_o`.
--!
--!  The `g_MSB_RIGHT` parameter determines how consecutive data words are
--!  joined together. The behaviour for the two possible cases is illustrated
--!  below (M=MSB, L=LSB, off=bit offset):
--!
--!                    _   __________   __________   __________   _
--!  True (MSB right)  _\ /_L_|____M_\ /_L_|____M_\ /_L_|____M_\ /_
--!                       <off>        <off>        <off>
--!                    _   __________   __________   __________   _
--!  False (MSB left)  _\ /_M____|_L_\ /_M____|_L_\ /_M____|_L_\ /_
--!                              <off>        <off>        <off>
--!
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 31-10-2023 Initial version called `stream_offset` (0.1)
--! @date 31-03-2025 Ported to colibri as `bit_shifter`
--! @version 0.2
--! @copyright CERN 2025
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;

----------------------------------------------------------------------------------------------------

entity bit_shifter is
  generic (
    g_DATA_WIDTH : positive := 8;   --! Input word width in terms of bits
    g_MSB_RIGHT  : boolean  := True --! Orientation of the input words
  );
  port (
    --! Clock and reset
    clk_i   : in    std_logic;
    reset_i : in    std_logic;

    --! Bit-offset
    offset_i : in    unsigned(log2ceil(g_DATA_WIDTH) - 1 downto 0);

    --! Data stream ports
    data_i : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    data_o : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0)
  );
end entity bit_shifter;

----------------------------------------------------------------------------------------------------

architecture rtl of bit_shifter is

  --! A record containing all registered signals
  type reg_t is record
    data_buf : std_logic_vector(2 * g_DATA_WIDTH - 1 downto 0);
    offset   : natural;
  end record reg_t;

  --! Initial register values
  constant c_REG_TYPE_INIT : reg_t :=
  (
    data_buf => (others => '0'),
    offset   => 0
  );

  --! Registered signals
  signal r, rin : reg_t := c_REG_TYPE_INIT;

begin

  ----------------------------------------------------------------------------
  --! Two-process structure (see https://www.gaisler.com/doc/vhdl2proc.pdf)
  ----------------------------------------------------------------------------

  proc_comb : process (reset_i, r, offset_i, data_i) is

    variable v : reg_t;

  begin

    -- Assign current registered values
    v := r;

    -- Register the offset setting and shift in new data
    v.offset := to_integer(offset_i);
    -- Make sure new data is shifted in "MSB first"
    if (g_MSB_RIGHT) then
      v.data_buf := data_i & r.data_buf(r.data_buf'left downto g_DATA_WIDTH);
    else
      v.data_buf := r.data_buf(r.data_buf'left - g_DATA_WIDTH downto 0) & data_i;
    end if;

    -- Synchronous reset (active high)
    if (reset_i = '1') then
      v := c_REG_TYPE_INIT;
    end if;

    -- Drive register inputs
    rin <= v;

    -- Output buffered data with an offset (depending on the orientation)
    if (g_MSB_RIGHT) then
      data_o <= r.data_buf(r.data_buf'left - r.offset downto r.data_buf'length - r.offset - g_DATA_WIDTH);
    else
      data_o <= r.data_buf(r.offset + g_DATA_WIDTH - 1 downto r.offset);
    end if;

  end process proc_comb;

  r <= rin when rising_edge(clk_i);

end architecture rtl;

----------------------------------------------------------------------------------------------------
