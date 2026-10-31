--==================================================================================================
--! @brief Simple Avalon Stream to RAM writer
--!
--!  This component performs sequential writes of the data presented on the
--!  Avalon stream input interface through a simple RAM interface.
--!
--! The data to be written is passed to the component via a packeted Avalon-ST
--! input interface. The start address is configured at the start of packet (SoP)
--! via the `start_address_i` sideband. Raised `snk_sop_i` marks the first word
--! to be written. Subsequent valid words on the input interface are written via
--! the output RAM interface in a sequential manner, i.e. to incrementing word
--! addresses.
--! The write sequence stops when an end of packet (EoP) beat is received on the
--! input interface (`snk_eop_i` marking the last word to be written).
--! It is not necessary to stop the write sequence with an EoP; if an SoP is
--! asserted during an active sequence, the component continues writing from the
--! new `start_addr_i`.
--!
--! { signal : [
--!   { name: "clk",            wave: "p....|..."},
--!   {},
--!   [ "Avalon-ST",
--!     { name: "start_addr_i", wave: "x=x..|...", data: "a"},
--!     { name: "snk_sop_i",    wave: "010..|..."},
--!     { name: "snk_eop_i",    wave: "0....|10."},
--!     { name: "snk_valid_i",  wave: "01...|.0."},
--!     { name: "snk_data_i",   wave: "x===.|=x.", data: "d0 d1 ... dn"},
--!   ],
--!   {},
--!   [ "RAM write",
--!     { name: "wr_en_o",      wave: "0.1..|..0"},
--!     { name: "wr_addr_o",    wave: "x.===|.=x", data: "a a+1 ... a+n"},
--!     { name: "wr_data_o",    wave: "x.===|.=x", data: "d0 d1 ... dn"},
--!   ],
--! ],
--!   config: { hscale: 2 }
--! }
--!
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 16-05-2025 Created
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

entity avst_ram_write is
  generic (
    --! Data width in bits
    g_DATA_WIDTH : positive := 8;
    --! Address width in bits
    g_ADDR_WIDTH : positive := 8
  );
  port (
    --! Clock and reset
    clk_i   : in    std_logic;
    reset_i : in    std_logic;

    --! Avalon-ST input interface (with start address sideband)
    start_addr_i : in    unsigned(g_ADDR_WIDTH - 1 downto 0);
    snk_sop_i    : in    std_logic;
    snk_eop_i    : in    std_logic;
    snk_data_i   : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    snk_valid_i  : in    std_logic;

    --! RAM write interface
    wr_en_o   : out   std_logic;
    wr_addr_o : out   unsigned(g_ADDR_WIDTH - 1 downto 0);
    wr_data_o : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0)
  );
end entity avst_ram_write;

----------------------------------------------------------------------------------------------------

architecture rtl of avst_ram_write is

  -- RAM write interface record
  type ram_wr_t is record
    en   : std_logic;
    addr : wr_addr_o'subtype;
    data : std_logic_vector(wr_data_o'range);
  end record ram_wr_t;

  constant c_RAM_WR_INIT : ram_wr_t :=
  (
    en   => '0',
    addr => (others => '0'),
    data => (others => '0')
  );

  -- A record containing all registered signals
  type reg_t is record
    active : std_logic;
    addr   : wr_addr_o'subtype;
    ram_wr : ram_wr_t;
  end record reg_t;

  -- Initial register values
  constant c_REG_TYPE_INIT : reg_t :=
  (
    active => '0',
    addr   => (others => '0'),
    ram_wr => c_RAM_WR_INIT
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

    -- Start on the start of packet
    if (snk_sop_i and snk_valid_i) then
      v.active := '1';
      v.addr   := start_addr_i;
    end if;

    -- Input handshake
    if (v.active and snk_valid_i) then
      v.ram_wr :=
      (
        en   => '1',
        addr => v.addr,
        data => snk_data_i
      );
      v.addr   := v.addr + 1;
    else
      v.ram_wr := c_RAM_WR_INIT;
    end if;

    -- Stop on end of packet
    if (snk_eop_i and snk_valid_i) then
      v.active := '0';
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
  wr_en_o   <= r.ram_wr.en;
  wr_addr_o <= r.ram_wr.addr;
  wr_data_o <= r.ram_wr.data;

end architecture rtl;

----------------------------------------------------------------------------------------------------
