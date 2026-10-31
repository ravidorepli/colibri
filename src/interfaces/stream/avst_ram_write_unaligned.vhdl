--! @file avst_ram_write_unaligned.vhdl
--! @brief Avalon Stream to RAM writer with unaligned (byte-addressable) access
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 10-06-2025 Created
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
--! @brief Avalon Stream to RAM writer with unaligned (byte-addressable) access
--! @details
--!
--!  Writes Avalon-ST packets to byte-addressable memory locations.
--!  This component is meant to be used with memory components which
--!  support byte-enabled writing (`wr_be_o` is the byte-enable vector).
--!
--!  At Start of Packet (SoP) the `start_addr_i` sideband should be set to
--!  the initial byte address. All subsequent data will be written sequentially.
--!  Writing finishes when the End of Packet (EoP) is asserted.
--!
--!  Due to unaligned memory access an additional write cycle might be required
--!  after the EoP, during which the `snk_ready_o` will be deasserted causing
--!  slight backpreassure.
--!
--!  The output to RAM has a constant 2CC delay after the Avalon-ST input.
--!
--!  The following diagram depicts two example packets:
--!   - 1st: The combination of address skew and packet size cause an additional
--!   write at the end of packet (`snk_ready_o` falls for 1CC)
--!   - 2nd: Here no additional write is needed
--!
--!  {"signal":[
--!     {"name":"clk_i",        "wave":"p............."},
--!     {},
--!     {"name":"start_addr_i", "wave":"x3x...4.x..5x.", "data":"3 33 ...",
--!                             "node":".1....a....e.."},
--!     {},
--!     {"name":"snk_sop_i",    "wave":"010...1.0..10."},
--!     {"name":"snk_eop_i",    "wave":"0....10...10..",
--!                             "node":".....d........"},
--!     {"name":"snk_valid_i",  "wave":"01............"},
--!     {"name":"snk_ready_o",  "wave":"1.....01......",
--!                             "node":".......b......"},
--!     {"name":"snk_data_i",   "wave":"x333334.444555",
--!                             "data":"wxyz wxyz wxyz wxyz wxy0 ijkl ijkl ijkl i000 ... ... ...",
--!                             "node":".2.........f.."},
--!     {"name":"snk_empty_i",  "wave":"x....=x...=x..", "data":"1 3"},
--!     {},
--!     {"name":"wr_be_o",      "wave":"x..==...===.==", "data":"0001 1111 1100 0111 1111 1100 ..."},
--!     {"name":"wr_addr_o",    "wave":"x..33333344445", "data":"0 1 2 3 4 5 8 9 10 11 ...",
--!                             "node":"...3.....c...g"},
--!     {"name":"wr_data_o",    "wave":"x..33333344445",
--!                             "data":"000w xyzw xyzw xyzw xyzw xy00 0ijk lijk lijk li00 ..."},
--!     {                       "node":"...x.....y...z"}
--!     ],
--!   "edge":["1->2", "2->3 2CC", "a->b", "b->c 2CC", "d->b +1 write", "x<->y 5 + 1", "y<->z 4 + 0",
--!           "e->f", "f->g 2CC"]
--!  }
--!
--!  Writing of the input packet can also be terminated without an EoP being
--!  reached, by asserting the `flush_i` port. This will "flush" any data bytes
--!  remaining in the internal buffer to the RAM.
--!  This is useful, when the user does not know in advance which of the input
--!  data beats will be the EoP and the packet needs to be terminated when all
--!  data has already been passed to the component.
--!  Here is an example of using this port:
--!
--!  {"signal":[
--!     {"name":"clk_i",        "wave":"p............"},
--!     {},
--!     {"name":"start_addr_i", "wave":"x3x..........", "data":"3"},
--!     {},
--!     {"name":"flush_i",      "wave":"0........10.."},
--!     {"name":"snk_sop_i",    "wave":"010.........."},
--!     {"name":"snk_valid_i",  "wave":"01....0......"},
--!     {"name":"snk_ready_o",  "wave":"1............"},
--!     {"name":"snk_data_i",   "wave":"x33333x......", "data":"abcd efgh ijkl mnop rstu"},
--!     {},
--!     {"name":"wr_be_o",      "wave":"x..==...=..=x", "data":"0001 1111 0000 1110"},
--!     {"name":"wr_addr_o",    "wave":"x..33333x..3x", "data":"0 1 2 3 4 5"},
--!     {"name":"wr_data_o",    "wave":"x..33333x..3x", "data":"000a bcde fghi jklm nopr stu0"},
--!     ]
--!  }
--!
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity avst_ram_write_unaligned is
  generic (
    --! Byte width in bits
    g_BYTE_WIDTH : positive := 8;
    --! Bytes per data word
    g_WORD_BYTES : positive := 8;
    --! RAM depth in terms of the number of words
    g_RAM_DEPTH  : positive := 16
  );
  port (
    --! Clock and reset
    clk_i   : in    std_logic;
    reset_i : in    std_logic;

    --! Avalon-ST input interface
    snk_data_i  : in    std_logic_vector(g_WORD_BYTES * g_BYTE_WIDTH - 1 downto 0);
    snk_empty_i : in    unsigned(maximum(log2ceil(g_WORD_BYTES), 1) - 1 downto 0);
    snk_sop_i   : in    std_logic;
    snk_eop_i   : in    std_logic;
    snk_valid_i : in    std_logic;
    snk_ready_o : out   std_logic;

    --! Start address in terms of bytes (input sideband - set at the SoP)
    start_addr_i : in    unsigned(log2ceil(g_RAM_DEPTH * g_WORD_BYTES) - 1 downto 0);
    --! Flush request - finalizes the write request before an `src_eop_i`
    flush_i      : in    std_logic;

    --! RAM write interface (word-addressable with byte-enable)
    wr_be_o   : out   std_logic_vector(g_WORD_BYTES - 1 downto 0);
    wr_addr_o : out   unsigned(log2ceil(g_RAM_DEPTH) - 1 downto 0);
    wr_data_o : out   std_logic_vector(g_WORD_BYTES * g_BYTE_WIDTH - 1 downto 0)
  );
end entity avst_ram_write_unaligned;

----------------------------------------------------------------------------------------------------

architecture rtl of avst_ram_write_unaligned is

  --! FSM states
  type state_t is (
    S_IDLE,  --! Waiting for new data packet
    S_SOP,   --! Start of Packet - start writing
    S_WRITE, --! Writing packet body
    S_EOP    --! End of Packet - finish writing
  );

  --! RAM write interface record
  type ram_wr_t is record
    be   : wr_be_o'subtype;   --! Byte-enable vector
    addr : wr_addr_o'subtype; --! Word-address
    data : wr_data_o'subtype; --! Data word
  end record ram_wr_t;

  constant c_RAM_WR_INIT : ram_wr_t :=
  (
    be   => (others => '0'),
    addr => (others => '0'),
    data => (others => '0')
  );

  --! A record containing all registered signals
  type reg_t is record
    state         : state_t;                                              --! FSM state
    snk_ready     : std_logic;                                            --! AVST ready output signal
    snk_eop       : std_logic;                                            --! registered EoP
    buf_bytes     : integer range 0 to 2 * g_WORD_BYTES - 1;              --! Number of valid buffered bytes
    byte_skew     : integer range 0 to 2 * g_WORD_BYTES - 1;              --! Current byte-addr. skew
    buf_valid     : std_logic;                                            --! Valid data is in the buffer
    buf_data      : std_logic_vector(2 * snk_data_i'length - 1 downto 0); --! buffer
    start_addr    : wr_addr_o'subtype;                                    --! registered init. word-address
    ram_wr        : ram_wr_t;                                             --! RAM write interface
    packet_active : std_logic;                                            --! Is a input packet currently active?
  end record reg_t;

  --! Initial register values
  constant c_REG_TYPE_INIT : reg_t :=
  (
    state         => S_IDLE,
    snk_ready     => '0',
    snk_eop       => '0',
    buf_valid     => '0',
    buf_data      => (others => '0'),
    buf_bytes     => 0,
    start_addr    => (others => '0'),
    byte_skew     => 0,
    ram_wr        => c_RAM_WR_INIT,
    packet_active => '0'
  );

  --! Registered signals
  signal r, rin : reg_t := c_REG_TYPE_INIT;

begin ----------------------------------------------------------------------------------------------

  ------------------------------------------------------------------------------
  --! Two-process structure (see https://www.gaisler.com/doc/vhdl2proc.pdf)
  ------------------------------------------------------------------------------
  proc_comb : process (all) is

    variable v : reg_t;

    --! State transition at the SoP --------------------------------------------
    procedure start_of_packet is
    begin

      -- Determine new write address and byte-skew
      v.start_addr := to_unsigned(to_integer(start_addr_i / g_WORD_BYTES), wr_addr_o'length);
      v.byte_skew  := to_integer(start_addr_i mod g_WORD_BYTES);
      v.state      := S_SOP;

      -- Create 1CC of back-pressure, when more than 1 word remains to be written
      -- (for 1-beat packets)
      if (snk_eop_i) then
        v.snk_ready := bool_to_sl(g_WORD_BYTES - to_integer(snk_empty_i) + v.byte_skew <= g_WORD_BYTES);
      end if;

    end procedure start_of_packet; ---------------------------------------------

    --! State transition at the EoP --------------------------------------------
    procedure end_of_packet is
    begin

      -- Create 1CC of back-pressure, when more than 1 word remains to be written
      v.snk_ready := bool_to_sl(v.buf_bytes + g_WORD_BYTES - to_integer(snk_empty_i) <= g_WORD_BYTES);
      v.state     := S_EOP;

    end procedure end_of_packet; -----------------------------------------------

  begin

    -- Assign current registered values
    v := r;

    -- Default register assignments
    v.snk_ready := '1';
    v.buf_valid := '0';
    v.snk_eop   := snk_eop_i;

    -- Finite State Machine ----------------------------------------------------
    case r.state is

      when S_IDLE => -------------------------------------------------------
        v.ram_wr    := c_RAM_WR_INIT;
        v.byte_skew := 0;

        if (snk_valid_i and snk_sop_i and r.snk_ready) then
          start_of_packet;
        end if;

      when S_SOP => --------------------------------------------------------

        -- Set the initial RAM write byte-enable mask
        for i in wr_be_o'range loop
          v.ram_wr.be(wr_be_o'left - i) := bool_to_sl(i >= r.byte_skew and i < r.byte_skew + r.buf_bytes);
        end loop;

        -- Set the initial write address
        v.ram_wr.addr := r.start_addr;

        -- Set the data word to write
        v.ram_wr.data :=
          r.buf_data(snk_data_i'left + r.byte_skew * g_BYTE_WIDTH downto r.byte_skew * g_BYTE_WIDTH);

        -- Single-beat packet with one write
        if (r.buf_bytes + r.byte_skew <= g_WORD_BYTES) then
          v.buf_bytes := 0;

          -- Immediate start of next packet
          if (snk_valid_i and snk_sop_i and r.snk_ready) then
            start_of_packet;
          else
            v.state := S_IDLE;
          end if;
        else
          v.buf_bytes := r.buf_bytes + r.byte_skew - g_WORD_BYTES;
        end if;

        -- Single-beat packet with two writes
        if (r.snk_eop or flush_i) then
          if (r.buf_bytes + r.byte_skew > g_WORD_BYTES) then
            v.buf_data := r.buf_data(snk_data_i'range) & std_logic_vector(to_unsigned(0, snk_data_i'length));
            v.state    := S_EOP;
          end if;

        -- 2-beat packet
        elsif (snk_eop_i and snk_valid_i) then
          end_of_packet;

        -- Longer packet - write the body
        else
          v.state := S_WRITE;
        end if;

      when S_WRITE => ------------------------------------------------------

        -- Write when valid data is in the buffer
        if (r.buf_valid) then
          v.ram_wr    :=
          (
            be => (others => '1'), -- Write full words during packet body
            addr => r.ram_wr.addr + 1,
            data => r.buf_data(snk_data_i'left + r.byte_skew * g_BYTE_WIDTH downto r.byte_skew * g_BYTE_WIDTH)
          );
          v.buf_bytes := r.buf_bytes - g_WORD_BYTES;
        else
          v.ram_wr.be := (others => '0');
        end if;

        -- End of Packet
        if (snk_eop_i and snk_valid_i) then
          end_of_packet;
        end if;

        -- Finish writing without an EoP - flush any remaining buffer contents
        if (flush_i) then
          v.buf_bytes := r.byte_skew;
          v.buf_data  := r.buf_data(snk_data_i'range) & std_logic_vector(to_unsigned(0, snk_data_i'length));
          v.state     := S_EOP;
        end if;

      when S_EOP => --------------------------------------------------------

        -- Update write address and data
        v.ram_wr.addr := r.ram_wr.addr + 1;
        v.ram_wr.data := r.buf_data(snk_data_i'left + r.byte_skew * g_BYTE_WIDTH downto r.byte_skew * g_BYTE_WIDTH);

        -- Flush the rest of the buffer - can be more that one full word
        if (r.buf_bytes > g_WORD_BYTES) then
          v.ram_wr.be := (others => '1');
          v.buf_data  := r.buf_data(snk_data_i'range) & std_logic_vector(to_unsigned(0, snk_data_i'length));
          v.buf_bytes := r.buf_bytes - g_WORD_BYTES;
        else

          for i in wr_be_o'range loop
            v.ram_wr.be(wr_be_o'left - i) := bool_to_sl(i < r.buf_bytes);
          end loop;

          v.buf_bytes := 0;
        end if;

        -- Packet fully written - progress the FSM
        if (v.buf_bytes = 0) then
          if (snk_valid_i and snk_sop_i and r.snk_ready) then
            start_of_packet;
          else
            v.state := S_IDLE;
          end if;
        end if;

      when others => -------------------------------------------------------
        v.state := S_IDLE;

    end case; ------------------------------------------------------------------

    -- Input Avalon-ST handshake
    if (snk_valid_i and r.snk_ready) then
      v.packet_active := r.packet_active or snk_sop_i;

      if (v.packet_active) then
        v.buf_data  := v.buf_data(snk_data_i'range) & snk_data_i;
        v.buf_bytes := v.buf_bytes + g_WORD_BYTES - to_integer(snk_empty_i);
        v.buf_valid := '1';
      end if;

      if (snk_eop_i) then
        v.packet_active := '0';
      end if;
    end if;

    if (flush_i) then
      v.packet_active := '0';
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
  snk_ready_o <= r.snk_ready;
  wr_be_o     <= r.ram_wr.be;
  wr_addr_o   <= r.ram_wr.addr;
  wr_data_o   <= r.ram_wr.data;

end architecture rtl;

----------------------------------------------------------------------------------------------------
