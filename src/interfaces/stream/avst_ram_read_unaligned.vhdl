--! @file avst_ram_read_unaligned.vhdl
--! @brief Avalon Stream to RAM reader with unaligned (byte-addressable) access
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 18-06-2025 Created
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
--! @brief Avalon Stream to RAM reader with unaligned (byte-addressable) access
--! @details
--!
--!  Reads Avalon-ST packets from byte-addressable memory locations.
--!
--!  Reading is initiated by setting the `start_i` high. The starting byte
--!  address and length (in terms of bytes) should be set at the same time using
--!  the `start_addr_i` and `length_i` ports.
--!
--!  Reading can only be initiated when component is not busy
--!  (when `busy_o = '0`).
--!
--!  The data is read through a simple RAM interface and presented on the output
--!  Avalon Stream interface. The final beat (`src_eop_o` asserted) of the
--!  Avalon packet may be partially empty - the number of empty bytes (located
--!  at LSB) is indicated on the `src_empty_o` bus.
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity avst_ram_read_unaligned is
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
    start_addr_i : in    unsigned(log2ceil(g_RAM_DEPTH * g_WORD_BYTES) - 1 downto 0);
    length_i     : in    unsigned(log2ceil(g_RAM_DEPTH * g_WORD_BYTES) downto 0);
    start_i      : in    std_logic;
    busy_o       : out   std_logic;

    --! RAM read interface
    rd_en_o   : out   std_logic;
    rd_addr_o : out   unsigned(log2ceil(g_RAM_DEPTH) - 1 downto 0);
    rd_data_i : in    std_logic_vector(g_WORD_BYTES * g_BYTE_WIDTH - 1 downto 0)
  );
end entity avst_ram_read_unaligned;

----------------------------------------------------------------------------------------------------

architecture rtl of avst_ram_read_unaligned is

  --! FSM states
  type state_t is (
    S_IDLE, --! Waiting for a start command
    S_INIT, --! Read initial 2 words into the buffer
    S_SOP,  --! Start a new packet on the Avalon output
    S_BODY, --! Reading packet body
    S_EOP   --! End the Avalon packet
  );

  --! RAM write interface record
  type ram_rd_t is record
    en   : rd_en_o'subtype;   --! Read enable
    addr : rd_addr_o'subtype; --! Word-address
  end record ram_rd_t;

  constant c_RAM_RD_INIT : ram_rd_t :=
  (
    en   => '0',
    addr => (others => '0')
  );

  --! A record containing all registered signals
  type reg_t is record
    state      : state_t;                                 --! FSM state
    avst_src   : avst_master_t(data(src_data_o'range), empty(src_empty_o'range));
    ram_rd     : ram_rd_t;                                --! RAM read interface
    rd_cntdwn  : length_i'subtype;                        --! Read byte-countdown
    out_cntdwn : length_i'subtype;                        --! Output byte-countdown
    skew       : integer range 0 to 2 * g_WORD_BYTES - 1; --! Addr. byte-skew
    buf_bytes  : integer range 0 to 2 * g_WORD_BYTES;     --! Num. of bytes in the buffer
    buf_data   : std_logic_vector(2 * rd_data_i'length - 1 downto 0);
    rd_data    : rd_data_i'subtype;                       --! Stored RAM output data
    rd_valid   : std_logic;                               --! Stored data is valid
    ram_valid  : std_logic;                               --! RAM output is valid
    buf_fill   : std_logic;                               --! Force fill the buffer
  end record reg_t;

  --! Initial register values
  constant c_REG_TYPE_INIT : reg_t :=
  (
    state      => S_IDLE,
    avst_src   => avst_master_init(src_data_o'length, g_BYTE_WIDTH),
    ram_rd     => c_RAM_RD_INIT,
    rd_cntdwn  => (others => '0'),
    out_cntdwn => (others => '0'),
    skew       => 0,
    buf_bytes  => 0,
    buf_data   => (others => '0'),
    rd_data    => (others => '0'),
    ram_valid  => '0',
    rd_valid   => '0',
    buf_fill   => '0'
  );

  --! Registered signals
  signal r, rin : reg_t := c_REG_TYPE_INIT;

begin ----------------------------------------------------------------------------------------------

  ------------------------------------------------------------------------------
  --! Two-process structure (see https://www.gaisler.com/doc/vhdl2proc.pdf)
  ------------------------------------------------------------------------------
  proc_comb : process (all) is

    variable v : reg_t;

    --! Output data from buffer to the Avalon-ST -------------------------------
    procedure output_buf_data is
    begin

      -- Read from buffer at a skewed byte-address
      v.avst_src.data := r.buf_data(r.buf_data'left   - g_BYTE_WIDTH * r.skew downto
                                    r.buf_data'length - g_BYTE_WIDTH * r.skew - src_data_o'length);
      v.buf_bytes     := r.buf_bytes - g_WORD_BYTES;

      -- Update output byte-countdown
      if (r.out_cntdwn >= g_WORD_BYTES) then
        v.out_cntdwn := r.out_cntdwn - g_WORD_BYTES;
      else
        v.out_cntdwn := (others => '0');
      end if;

    end procedure output_buf_data; ---------------------------------------------

  begin --------------------------------------------------------------------------------------------

    -- Assign current registered values
    v := r;

    -- Output Avalon handshake - clear the interface
    if (r.avst_src.valid and src_ready_i) then
      v.avst_src := avst_master_init(src_data_o'length, g_BYTE_WIDTH);
    end if;

    -- Finite State Machine ----------------------------------------------------
    case r.state is

      when S_IDLE => -------------------------------------------------------
        v.ram_rd    := c_RAM_RD_INIT;
        v.buf_bytes := 0;

        if (start_i) then
          v.ram_rd.en   := '1';
          v.ram_rd.addr := to_unsigned(to_integer(start_addr_i) / g_WORD_BYTES, rd_addr_o'length);
          v.skew        := to_integer(start_addr_i) mod g_WORD_BYTES;
          v.rd_cntdwn   := length_i + v.skew;
          v.out_cntdwn  := length_i;
          v.state       := S_INIT;
        end if;

      when S_INIT => -------------------------------------------------------
        v.buf_fill := '1';

        -- Wait for the buffer to fill
        -- (there will be 2 full words buffered in the next state)
        if (r.buf_bytes = g_WORD_BYTES) then
          v.buf_fill := '0';
          v.state    := S_SOP;
        end if;

      when S_SOP => -------------------------------------------------------

        if (v.avst_src.valid = '0') then
          v.avst_src.valid := '1';
          v.avst_src.sop   := '1';

          -- Single-beat packet
          if (r.out_cntdwn <= g_WORD_BYTES) then
            v.avst_src.eop   := '1';
            v.avst_src.empty := to_unsigned(g_WORD_BYTES - to_integer(r.out_cntdwn), src_empty_o'length);
            output_buf_data;

            v.state := S_IDLE;

          -- Multi-beat packet
          else
            output_buf_data;

            -- Double-beat packet
            if (v.out_cntdwn <= g_WORD_BYTES) then
              if (not r.rd_valid) then
                v.buf_data := v.buf_data(rd_data_i'range) & r.rd_data;
              end if;
              v.state := S_EOP;
            else
              v.state := S_BODY;
            end if;
          end if;
        end if;

      when S_BODY => -------------------------------------------------------

        if (v.avst_src.valid = '0') then
          v.avst_src.valid := '1';
          output_buf_data;
        end if;

        if (v.out_cntdwn <= g_WORD_BYTES) then
          if (not r.rd_valid) then
            v.buf_data := v.buf_data(rd_data_i'range) & r.rd_data;
          end if;
          v.state := S_EOP;
        end if;

      when S_EOP => -------------------------------------------------------

        if (v.avst_src.valid = '0') then
          v.avst_src.valid := '1';
          v.avst_src.eop   := '1';
          v.avst_src.empty := to_unsigned(g_WORD_BYTES - to_integer(r.out_cntdwn), src_empty_o'length);
          output_buf_data;

          v.state := S_IDLE;
        end if;

      when others => -------------------------------------------------------
        v.state := S_IDLE;

    end case; ------------------------------------------------------------------

    -- Save the word read from RAM
    if (r.ram_valid = '1' and r.rd_valid = '0') then
      v.rd_data  := rd_data_i;
      v.rd_valid := '1';
    end if;

    -- Shift data read from RAM into the buffer
    if ((v.rd_valid = '1' or r.buf_fill = '1') and v.buf_bytes <= g_WORD_BYTES) then
      v.buf_data  := v.buf_data(rd_data_i'range) & v.rd_data;
      v.buf_bytes := v.buf_bytes + g_WORD_BYTES;
      v.rd_valid  := '0';
    end if;

    -- Conditionally enable RAM read ...
    if (r.state /= S_IDLE) then            -- In S_IDLE reading is initialized
      if (r.rd_cntdwn > g_WORD_BYTES) then -- when more data is needed
        if (v.rd_valid = '0') then         -- only when there is enough space in the buffer
          v.rd_cntdwn   := r.rd_cntdwn - g_WORD_BYTES;
          v.ram_rd.en   := '1';
          v.ram_rd.addr := r.ram_rd.addr + 1;
        else                               -- Pause due to back-pressure
          v.ram_rd.en := '0';
        end if;
      else                                 -- End of packet
        v.rd_cntdwn := (others => '0');
        v.ram_rd    := c_RAM_RD_INIT;
      end if;
    end if;

    -- RAM output becomes valid 1CC after enable
    -- and stays valid when data persists in the buffer (due to back-pressure)
    v.ram_valid := r.ram_rd.en or r.rd_valid;

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
  src_data_o  <= r.avst_src.data;
  src_empty_o <= r.avst_src.empty;
  src_sop_o   <= r.avst_src.sop;
  src_eop_o   <= r.avst_src.eop;
  src_valid_o <= r.avst_src.valid;

  rd_en_o   <= r.ram_rd.en;
  rd_addr_o <= r.ram_rd.addr;

  busy_o <= bool_to_sl(r.state /= S_IDLE);

end architecture rtl;

----------------------------------------------------------------------------------------------------
