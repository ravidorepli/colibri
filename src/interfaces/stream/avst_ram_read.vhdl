--==================================================================================================
--! @brief Simple Avalon Stream to RAM reader
--!
--!  This components performs sequential reads through a simple RAM interface
--!  and outputs the data on a packeted Avalon Stream interface.
--!
--!  The component is activated by asserting the `start_i` port. The `start_addr_i`
--!  and `length_i` ports need to be configured at the time of `start_i` assertion.
--!  After activation the data will be read sequentially starting from the configured
--!  address.
--!  Note: The `start_i` condition is only registered while component is not active
--!  (`busy_o = '0'`).
--!
--!  The component is deactivated automatically when the configured `length_i`
--!  **bytes** have been read. In case its configured to 0, the reading will
--!  go on indefinetly, until the `stop_i` port is asserted.
--!  Note: Asserting the `stop_i` signal will terminate any transfer short. If
--!  `stop_i` is asserted before an output packet starts (`src_sop_o` handshake)
--!  the packet will be skipped entirely.
--!
--!  Below waveform shows an example of 3 consecutive read sequences, with start
--!  addresses `a`, `b` and `c`. The requests are `L`, `M` and `N` words long;
--!  note that the `length_i` is configured in terms of bytes - `B` represents
--!  the `g_WORD_BYTES` generic.
--! { signal : [
--!   { name: "clk",            wave: "p................"},
--!   {},
--!   [ "Control interface",
--!     { name: "start_addr_i", wave: "x3x....4x.....5x.", data: "a b c"},
--!     { name: "length_i",     wave: "x3x....4x.....5x.", data: "L*B-x M*B N*B"},
--!     { name: "start_i",      wave: "010....10.....10."},
--!     { name: "stop_i",       wave: "0................"},
--!     { name: "busy_o",       wave: "0.1....01...0..1."},
--!   ],
--!   {},
--!   [ "RAM read",
--!     { name: "rd_en_o",      wave: "0.1..........0.1."},
--!     { name: "rd_addr_o",    wave: "x.333..344.4x.455", data: "a a+1 ... a+L-1 b b+1 ... b+M-1 c c+1"},
--!     { name: "rd_data_i",    wave: "x..333..344.4x.45", data: "w0 w1 ... wL-1 z0 z1 ... zM-1 u0"},
--!   ],
--!   {},
--!   [ "Avalon-ST output",
--!     { name: "src_data_o",   wave: "x...33.3..3444.4x", data: "w0 w1 ... wL-1 z0 z1 ... zM-1"},
--!     { name: "src_empty_o",  wave: "x.........3x...4x", data: "x 0"},
--!     { name: "src_eop_o",    wave: "0.........10...10"},
--!     { name: "src_sop_o",    wave: "0...10.....10...."},
--!     { name: "src_valid_o",  wave: "0...1...........0"},
--!     { name: "src_ready_i",  wave: "1....01.........."},
--!   ],
--! ],
--!   config: { hscale: 1 }
--! }
--!
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 19-05-2025 Created
--! @date 13-07-2026 Updated the output interface to produce Avalon-ST packets
--! @version 0.2
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

entity avst_ram_read is
  generic (
    --! Byte width in bits
    g_BYTE_WIDTH : positive := 8;
    --! Bytes per data word
    g_WORD_BYTES : positive;
    --! RAM depth in terms of the number of words
    g_RAM_DEPTH  : positive
  );
  port (
    --! Clock and reset
    clk_i   : in    std_logic;
    reset_i : in    std_logic;

    --! Avalon-ST output interface
    src_data_o  : out   std_logic_vector(g_WORD_BYTES * g_BYTE_WIDTH - 1 downto 0);
    src_empty_o : out   unsigned(maximum(log2ceil(g_WORD_BYTES), 1) - 1 downto 0);
    src_sop_o   : out   std_logic;
    src_eop_o   : out   std_logic;
    src_valid_o : out   std_logic;
    src_ready_i : in    std_logic;

    --! Control interface
    start_addr_i : in    unsigned(log2ceil(g_RAM_DEPTH) - 1 downto 0); --! Start address - set at start
    length_i     : in    unsigned(
      log2ceil(g_RAM_DEPTH * g_WORD_BYTES + 1) - 1 downto 0);          --! Number of **bytes** to read
    start_i      : in    std_logic;                                    --! Start reading
    stop_i       : in    std_logic;                                    --! Stop reading
    busy_o       : out   std_logic;                                    --! Reading ongoing

    --! RAM read interface
    rd_en_o   : out   std_logic;
    rd_addr_o : out   unsigned(log2ceil(g_RAM_DEPTH) - 1 downto 0);
    rd_data_i : in    std_logic_vector(g_WORD_BYTES * g_BYTE_WIDTH - 1 downto 0)
  );
end entity avst_ram_read;

----------------------------------------------------------------------------------------------------

architecture rtl of avst_ram_read is

  -- RAM read interface record
  type ram_rd_t is record
    en   : std_logic;
    addr : rd_addr_o'subtype;
  end record ram_rd_t;

  constant c_RAM_RD_INIT : ram_rd_t :=
  (
    en   => '0',
    addr => (others => '0')
  );

  -- A record containing all registered signals
  type reg_t is record
    busy       : std_logic;                                -- Is reading currently active
    continuous : std_logic;                                -- Is reading set with no length limit
    length     : length_i'subtype;                         -- Configured read length
    word_cnt   : unsigned(log2ceil(g_RAM_DEPTH) downto 0); -- Counter of read words
    addr       : rd_addr_o'subtype;                        -- Current read address
    ram_rd     : ram_rd_t;                                 -- Reading interface signals

    -- Data stream pipeline from RAM to the output
    avst_pipe : avst_master_array_t(0 to 2)(data(src_data_o'range), empty(src_empty_o'range));
  end record reg_t;

  -- Initial register values
  constant c_REG_TYPE_INIT : reg_t :=
  (
    busy       => '0',
    continuous => '0',
    length     => (others => '0'),
    word_cnt   => (others => '0'),
    addr       => (others => '0'),
    ram_rd     => c_RAM_RD_INIT,
    avst_pipe  => (others => avst_master_init(src_data_o'length, g_BYTE_WIDTH))
  );

  -- Registered signals
  signal r, rin : reg_t := c_REG_TYPE_INIT;

begin ----------------------------------------------------------------------------------------------

  ------------------------------------------------------------------------------
  --! Two-process structure (see https://www.gaisler.com/doc/vhdl2proc.pdf)
  ------------------------------------------------------------------------------
  proc_comb : process (all) is

    variable v : reg_t;

  begin

    -- Assign current registered values
    v := r;

    -- Start a new reading transaction
    if (start_i = '1' and r.busy = '0' and stop_i = '0') then
      v.busy       := '1';
      v.continuous := '0';
      v.addr       := start_addr_i;
      v.length     := length_i;
      v.word_cnt   := (others => '0');
    end if;

    -- Output Avalon Stream handshake
    if (src_ready_i = '1' and src_valid_o = '1') then
      v.avst_pipe(2) := c_REG_TYPE_INIT.avst_pipe(2);
    end if;

    -- Take in the data from RAM
    if (r.avst_pipe(0).valid = '1' and r.avst_pipe(1).valid = '0') then
      v.avst_pipe(1).data  := rd_data_i;
      v.avst_pipe(1).valid := '1';
      v.avst_pipe(1).sop   := r.avst_pipe(0).sop;
      v.avst_pipe(1).eop   := r.avst_pipe(0).eop;
      v.avst_pipe(1).empty := r.avst_pipe(0).empty;

      v.avst_pipe(0) := c_REG_TYPE_INIT.avst_pipe(0);
    end if;

    -- Present the read data on the output Avalon-ST
    if (v.avst_pipe(1).valid = '1' and v.avst_pipe(2).valid = '0') then
      v.avst_pipe(2).data  := v.avst_pipe(1).data;
      v.avst_pipe(2).empty := v.avst_pipe(1).empty;
      v.avst_pipe(2).eop   := v.avst_pipe(1).eop;
      v.avst_pipe(2).sop   := v.avst_pipe(1).sop;
      v.avst_pipe(2).valid := '1';

      v.avst_pipe(1) := c_REG_TYPE_INIT.avst_pipe(1);
    end if;

    v.ram_rd := c_RAM_RD_INIT;
    -- Read a word when the word buffer is free
    if (v.busy = '1' and v.avst_pipe(1).valid = '0') then
      v.ram_rd   :=
      (
        en => '1',
        addr => v.addr
      );
      v.addr     := v.addr + 1;
      v.word_cnt := v.word_cnt + 1;
    end if;

    -- Data is assumed to be read from RAM with 1 CC of delay
    if (r.ram_rd.en) then
      v.avst_pipe(0).valid := '1';
      if (r.word_cnt = 1) then
        v.avst_pipe(0).sop := not r.continuous;
        v.continuous       := bool_to_sl(r.length = 0);
      end if;
      if (r.length /= 0 and r.word_cnt = div_ceil(r.length,  g_WORD_BYTES)) then
        v.avst_pipe(0).eop   := '1';
        v.avst_pipe(0).empty := resize(
                                       g_WORD_BYTES * resize(r.word_cnt, r.length'length) - r.length,
           r.avst_pipe(0).empty'length);
      end if;
    end if;

    -- Length STOP condition
    if (v.word_cnt = div_ceil(v.length,  g_WORD_BYTES) and (v.length /= 0)) then
      v.busy := '0';
    end if;

    -- Input STOP request
    if (stop_i) then
      v.busy         := '0';
      v.ram_rd.en    := '0';
      v.avst_pipe(0) := c_REG_TYPE_INIT.avst_pipe(0);
      v.avst_pipe(1) := c_REG_TYPE_INIT.avst_pipe(1);

      v.avst_pipe(2).eop := v.avst_pipe(2).valid;
      if (v.avst_pipe(2).sop) then
        v.avst_pipe(2) := c_REG_TYPE_INIT.avst_pipe(2);
      end if;
    end if;

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
  busy_o      <= r.busy;
  rd_en_o     <= r.ram_rd.en;
  rd_addr_o   <= r.ram_rd.addr;
  src_data_o  <= r.avst_pipe(2).data;
  src_empty_o <= r.avst_pipe(2).empty;
  src_sop_o   <= r.avst_pipe(2).sop;
  src_eop_o   <= r.avst_pipe(2).eop;
  src_valid_o <= r.avst_pipe(2).valid;

end architecture rtl;

----------------------------------------------------------------------------------------------------
