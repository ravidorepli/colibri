--! @file packet_join.vhdl
--! @brief Joins consecutive Avalon-ST packets into one
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 28-07-2025 Created
--! @version 0.1
--! @copyright CERN 2025
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.types.all;
  use colibri.utils.all;

--==================================================================================================
--! @brief Joins consecutive Avalon-ST packets into one
--! @details
--!
--!  Multiple packets on the input Avalon-ST are joined into a single continuous
--!  packet at the output.
--!
--!  If any packet has empty symbols in its last word (as
--!  indicated by the `snk_empty_i` bus at EoP) they will be removed and the
--!  first symbols of the next packet will follow directly. The output packet
--!  may have some empty symbols in its last word.
--!
--!  SoP will be signalled on the output (`src_sop_o`) when the first input data
--!  is available. The output packet may be terminated with an EoP by marking
--!  the last input packet - to do that, assert 'last_i' any time before the
--!  `snk_eop_i` of the last packet.
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity packet_join is
  generic (
    --! Symbol width
    g_SYM_WIDTH : positive := 8;
    --! Data width in terms of symbols
    g_DATA_SYM  : positive := 4
  );
  port (
    --! Clock and reset
    clk_i   : in    std_logic;
    reset_i : in    std_logic;

    --! Last input packet marker
    last_i : in    std_logic;

    --! Avalon-ST input interface
    snk_data_i  : in    std_logic_vector(g_DATA_SYM * g_SYM_WIDTH - 1 downto 0);
    snk_empty_i : in    unsigned(maximum(log2ceil(g_DATA_SYM), 1) - 1 downto 0);
    snk_sop_i   : in    std_logic;
    snk_eop_i   : in    std_logic;
    snk_valid_i : in    std_logic;
    snk_ready_o : out   std_logic;

    --! Avalon-ST output interface
    src_data_o  : out   std_logic_vector(g_DATA_SYM * g_SYM_WIDTH - 1 downto 0);
    src_empty_o : out   unsigned(maximum(log2ceil(g_DATA_SYM), 1) - 1 downto 0);
    src_sop_o   : out   std_logic;
    src_eop_o   : out   std_logic;
    src_valid_o : out   std_logic;
    src_ready_i : in    std_logic
  );
end entity packet_join;

----------------------------------------------------------------------------------------------------

architecture rtl of packet_join is

  constant c_BUF_WORDS : positive := 3;

  --! A record containing all registered signals
  type reg_t is record
    avst_snk  : avst_slave_t;
    avst_src  : avst_master_t(data(src_data_o'range), empty(src_empty_o'range));
    buf_data  : std_logic_vector(c_BUF_WORDS * snk_data_i'length - 1 downto 0);
    buf_addr  : integer range 0 to c_BUF_WORDS * snk_data_i'length;
    buf_sop   : std_logic_vector(c_BUF_WORDS - 1 downto 0);
    buf_eop   : std_logic_vector(c_BUF_WORDS - 1 downto 0);
    buf_empty : uns_array_t(0 to c_BUF_WORDS - 1)(src_empty_o'range);
    first_pkt : std_logic;
    last_pkt  : std_logic;
  end record reg_t;

  --! Initial register values
  constant c_REG_TYPE_INIT : reg_t :=
  (
    avst_snk  => c_AVST_SLAVE_INIT,
    avst_src  => avst_master_init(src_data_o'length, g_SYM_WIDTH),
    buf_data  => (others => '0'),
    buf_addr  => 0,
    buf_sop   => (others => '0'),
    buf_eop   => (others => '0'),
    buf_empty => (others => (others => '0')),
    first_pkt => '1',
    last_pkt  => '0'
  );

  --! Registered signals
  signal r, rin : reg_t := c_REG_TYPE_INIT;

begin ----------------------------------------------------------------------------------------------

  ------------------------------------------------------------------------------
  --! Two-process structure (see https://www.gaisler.com/doc/vhdl2proc.pdf)
  ------------------------------------------------------------------------------
  proc_comb : process (all) is

    --! Registered signals
    variable v : reg_t;

    --! Shift array elements left by one place ----------------------
    function shift_left (arr : uns_array_t) return uns_array_t is

      variable v_out : arr'subtype;

    begin --------------------------------------------

      for i in v_out'left to v_out'right - 1 loop
        v_out(i) := arr(i + 1);
      end loop;

      v_out(v_out'right) := (others => '0');
      return v_out;

    end function shift_left; ----------------------------------------

    --! Generate a bit-mask with empty bits disabled
    impure function empty_mask return snk_data_i'subtype is

      variable v_out : snk_data_i'subtype;

    begin --------------------------------------------

      for i in 0 to g_DATA_SYM - 1 loop

        for j in 0 to g_SYM_WIDTH - 1 loop
          v_out(i * g_SYM_WIDTH + j) := bool_to_sl(i >= snk_empty_i);
        end loop;

      end loop;

      return v_out;

    end function empty_mask; ----------------------------------------

    --! Buffer variable used to shift the input data to correct position
    variable v_buf : v.buf_data'subtype;

  begin --------------------------------------------------------------------------------------------

    -- Assign current registered values
    v := r;

    --  register the last packet flag
    if (last_i) then
      v.last_pkt := '1';
    end if;

    -- Output handshake (clear the output interface, shift the buffer)
    if (r.avst_src.valid and src_ready_i) then
      v.avst_src  := avst_master_init(src_data_o'length, g_SYM_WIDTH);
      v.buf_data  := r.buf_data sll src_data_o'length;
      v.buf_addr  := r.buf_addr - src_data_o'length;
      v.buf_sop   := r.buf_sop srl 1;
      v.buf_eop   := r.buf_eop srl 1;
      v.buf_empty := shift_left(r.buf_empty);
    end if;

    -- Input handshake (take in the data)
    if (snk_valid_i and r.avst_snk.ready) then
      -- Shift the data to the correct position within the buffer
      v_buf(v.buf_data'left downto v.buf_data'length - snk_data_i'length) := snk_data_i and empty_mask;
      v_buf(v.buf_data'left - snk_data_i'length downto 0)                 := (others => '0');
      v_buf                                                               := v_buf srl v.buf_addr;
      v.buf_data                                                          := v.buf_data or v_buf;

      -- Set SoP if first packet
      if (snk_sop_i) then
        if (r.first_pkt) then
          v.buf_sop(v.buf_addr / src_data_o'length) := '1';
          v.first_pkt                               := '0';
        end if;
      end if;

      -- Set EoP on the last packet. Increment buffer address accordingly
      if (snk_eop_i) then
        v.buf_addr := v.buf_addr + (snk_data_i'length - g_SYM_WIDTH * to_integer(snk_empty_i));

        if (v.last_pkt) then
          v.buf_eop((v.buf_addr - 1) / src_data_o'length)   := '1';
          v.buf_empty((v.buf_addr - 1) / src_data_o'length) :=
            to_unsigned(g_DATA_SYM - (v.buf_addr mod src_data_o'length) / g_SYM_WIDTH,
                        src_empty_o'length);

          v.buf_addr  := div_ceil(v.buf_addr, snk_data_i'length) * snk_data_i'length;
          v.last_pkt  := '0';
          v.first_pkt := '1';
        end if;
      else
        v.buf_addr := v.buf_addr + snk_data_i'length;
      end if;
    end if;

    -- Input ready when buffer has enough space
    v.avst_snk.ready := bool_to_sl(v.buf_data'length - v.buf_addr >= snk_data_i'length);
    -- Output valid when buffer has enough data
    v.avst_src.valid := bool_to_sl(v.buf_addr >= src_data_o'length);
    -- Output the top buffered data bits
    v.avst_src.data  := v.buf_data(v.buf_data'left downto v.buf_data'length - src_data_o'length);
    v.avst_src.sop   := v.buf_sop(0);
    v.avst_src.eop   := v.buf_eop(0);
    v.avst_src.empty := v.buf_empty(0);

    -- Synchronous reset
    if (reset_i) then
      v := c_REG_TYPE_INIT;
    end if;

    -- Drive register inputs
    rin <= v;

  end process proc_comb;

  -- Drive sequential logic
  r <= rin when rising_edge(clk_i);

  -- Drive outputs
  snk_ready_o <= r.avst_snk.ready;
  src_data_o  <= r.avst_src.data;
  src_empty_o <= r.avst_src.empty;
  src_sop_o   <= r.avst_src.sop;
  src_eop_o   <= r.avst_src.eop;
  src_valid_o <= r.avst_src.valid;

end architecture rtl;

----------------------------------------------------------------------------------------------------
