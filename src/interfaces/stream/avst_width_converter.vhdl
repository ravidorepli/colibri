--==================================================================================================
--! @brief Avalon-ST width converter
--!
--!  Converts the data width of an Avalon stream, taking into account the packet
--!  delimiters (Start and End of Packet) and empty symbols.
--!  This component does not convert the symbol width - it is expected to be the
--!  same for the input and output streams.
--!
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 24-03-2025 Created
--! @version 0.1
--! @copyright CERN 2025
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.types.all;
  use colibri.utils.all;

----------------------------------------------------------------------------------------------------

entity avst_width_converter is
  generic (
    --! Symbol width
    g_SYM_WIDTH  : positive := 8;
    --! Input data width in terms of symbols
    g_INPUT_SYM  : positive := 16;
    --! Output data width in terms of symbols
    g_OUTPUT_SYM : positive := 1
  );
  port (
    --! Clock and reset
    clk_i   : in    std_logic;
    reset_i : in    std_logic;

    --! Avalon stream input
    snk_ready_o : out   std_logic;
    snk_valid_i : in    std_logic;
    snk_sop_i   : in    std_logic;
    snk_eop_i   : in    std_logic;
    snk_empty_i : in    unsigned(maximum(log2ceil(g_INPUT_SYM), 1) - 1 downto 0);
    snk_data_i  : in    std_logic_vector(g_SYM_WIDTH * g_INPUT_SYM - 1 downto 0);

    --! Avalon stream output
    src_ready_i : in    std_logic;
    src_valid_o : out   std_logic;
    src_sop_o   : out   std_logic;
    src_eop_o   : out   std_logic;
    src_empty_o : out   unsigned(maximum(log2ceil(g_OUTPUT_SYM), 1) - 1 downto 0);
    src_data_o  : out   std_logic_vector(g_SYM_WIDTH * g_OUTPUT_SYM - 1 downto 0)
  );
end entity avst_width_converter;

----------------------------------------------------------------------------------------------------

architecture rtl of avst_width_converter is

  --! Input/output data bus widths in terms of bits
  constant c_INPUT_WIDTH  : positive := snk_data_i'length;
  constant c_OUTPUT_WIDTH : positive := src_data_o'length;

  -- How many input words to buffer
  constant c_BUF_WORDS : positive := div_ceil(g_OUTPUT_SYM, g_INPUT_SYM) + 1;
  constant c_BUF_SYM   : positive := c_BUF_WORDS * g_INPUT_SYM;
  constant c_BUF_BITS  : positive := c_BUF_SYM * g_SYM_WIDTH;

  -- A record containing all registered signals

  type reg_t is record
    avst_src  : avst_master_t(data(src_data_o'range), empty(src_empty_o'range));
    snk_ready : std_logic;                                 -- Input Avalon-ST ready
    buf       : std_logic_vector(c_BUF_BITS - 1 downto 0); -- Data buffer
    sym_cnt   : integer range 0 to c_BUF_SYM;              -- Symbol counter
    bit_cnt   : integer range 0 to c_BUF_BITS;             -- Bit counter
    sop_buf   : std_logic_vector(c_BUF_SYM - 1 downto 0);  -- Start of Packet signal buffer
    eop_buf   : std_logic_vector(c_BUF_SYM - 1 downto 0);  -- End of Packet signal buffer
  end record reg_t;

  -- Initial register values
  constant c_REG_TYPE_INIT : reg_t :=
  (
    avst_src  => avst_master_init(c_OUTPUT_WIDTH, g_SYM_WIDTH),
    snk_ready => '0',
    buf       => (others => '0'),
    sym_cnt   => 0,
    bit_cnt   => 0,
    sop_buf   => (others => '0'),
    eop_buf   => (others => '0')
  );

  -- Registered signals
  signal r, rin : reg_t := c_REG_TYPE_INIT;

  ------------------------------------------------------------------------------
  -- Contruct a new SoP buffer entry (mark first symbol with SoP)
  ------------------------------------------------------------------------------
  function sop_tail (sop : std_logic) return std_logic_vector is

    variable v_out : std_logic_vector(g_INPUT_SYM - 1 downto 0) := (others => '0');

  begin

    v_out(v_out'left) := sop;
    return v_out;

  end function sop_tail;

  ------------------------------------------------------------------------------
  -- Contruct a new EoP buffer entry (mark only one symbol with EoP)
  ------------------------------------------------------------------------------
  function eop_tail (eop : std_logic; empty : unsigned) return std_logic_vector is

    variable v_out : std_logic_vector(g_INPUT_SYM - 1 downto 0) := (others => '0');

  begin

    v_out(to_integer(empty)) := eop;
    return v_out;

  end function eop_tail;

  ------------------------------------------------------------------------------
  -- Determine whether the next output work is the End of Packet
  ------------------------------------------------------------------------------
  function is_eop (eop_buf : r.eop_buf'subtype; ptr : natural) return std_logic is
  begin

    if (ptr = 0) then
      return '0';
    elsif (ptr < g_OUTPUT_SYM) then
      return or eop_buf(ptr - 1 downto 0);
    else
      return or eop_buf(ptr - 1 downto ptr - g_OUTPUT_SYM);
    end if;

  end function is_eop;

  ------------------------------------------------------------------------------
  -- Determine the number of empty symbols in the output word
  ------------------------------------------------------------------------------
  function get_empty (eop_buf : r.eop_buf'subtype; ptr : natural) return natural is
  begin

    for i in 1 to g_OUTPUT_SYM loop

      if (i > ptr) then
        return g_OUTPUT_SYM - i + 1;
      elsif eop_buf(ptr - i) then
        return g_OUTPUT_SYM - i;
      end if;

    end loop;

    return 0;

  end function get_empty;

begin ----------------------------------------------------------------------------------------------

  ------------------------------------------------------------------------------
  --! Two-process structure (see https://www.gaisler.com/doc/vhdl2proc.pdf)
  ------------------------------------------------------------------------------

  proc_comb : process (r, reset_i, snk_valid_i, snk_sop_i, snk_eop_i, snk_empty_i, snk_data_i, src_ready_i) is

    -- Registered values as variable
    variable v : reg_t;

    variable v_padded_buf : std_logic_vector(r.buf'length + c_OUTPUT_WIDTH - 1 downto 0) := (others => '0');

  begin

    v_padded_buf(v_padded_buf'left downto c_OUTPUT_WIDTH) := r.buf;

    -- Assign current registered values
    v := r;

    -- Input interface handshake: Store inputs in their buffers
    if (r.snk_ready and snk_valid_i) then
      v.buf     := r.buf(r.buf'left - snk_data_i'length downto 0) & snk_data_i;
      v.sym_cnt := r.sym_cnt + g_INPUT_SYM;
      v.bit_cnt := r.bit_cnt + snk_data_i'length;
      v.sop_buf := r.sop_buf(r.sop_buf'left - g_INPUT_SYM downto 0) & sop_tail(snk_sop_i);
      v.eop_buf := r.eop_buf(r.eop_buf'left - g_INPUT_SYM downto 0) & eop_tail(snk_eop_i, snk_empty_i);
    end if;

    -- Output interface handshake: Invalidate the output
    if (src_ready_i and r.avst_src.valid) then
      v.avst_src := avst_master_init(c_OUTPUT_WIDTH, g_SYM_WIDTH);
    end if;

    -- Output new data when current has been accepted
    if (v.avst_src.valid = '0') then
      if (is_eop(r.eop_buf, r.sym_cnt) = '1') then
        v.avst_src :=
        (
          data => v_padded_buf(c_OUTPUT_WIDTH + r.bit_cnt - 1 downto r.bit_cnt),
          empty => to_unsigned(get_empty(r.eop_buf, r.sym_cnt), v.avst_src.empty'length),
          sop => r.sop_buf(r.sym_cnt - 1),
          eop => '1',
          valid => '1'
        );
        v.sym_cnt  := v.sym_cnt - g_OUTPUT_SYM + to_integer(v.avst_src.empty);
        v.sym_cnt  := v.sym_cnt - v.sym_cnt mod g_INPUT_SYM;
        v.bit_cnt  := v.sym_cnt * g_SYM_WIDTH;
      elsif (r.sym_cnt >= g_OUTPUT_SYM) then
        v.avst_src :=
        (
          data => r.buf(r.bit_cnt - 1 downto r.bit_cnt - c_OUTPUT_WIDTH),
          empty => to_unsigned(0, v.avst_src.empty'length),
          sop => r.sop_buf(r.sym_cnt - 1),
          eop => '0',
          valid => '1'
        );
        v.bit_cnt  := v.bit_cnt - c_OUTPUT_WIDTH;
        v.sym_cnt  := v.sym_cnt - g_OUTPUT_SYM;
      end if;
    end if;

    -- Input ready when sufficient space is available
    v.snk_ready := bool_to_sl(c_BUF_SYM - v.sym_cnt >= g_INPUT_SYM);

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
  snk_ready_o <= r.snk_ready;
  src_data_o  <= r.avst_src.data;
  src_sop_o   <= r.avst_src.sop;
  src_eop_o   <= r.avst_src.eop;
  src_empty_o <= r.avst_src.empty;
  src_valid_o <= r.avst_src.valid;

end architecture rtl;

----------------------------------------------------------------------------------------------------
