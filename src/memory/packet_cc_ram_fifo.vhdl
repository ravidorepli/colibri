--! @file packet_cc_ram_fifo.vhdl
--! @brief Packet based FIFO with SDP dual-clock RAM storage
--! @author Alberto Perro
--! @date 20-04-2026 Created
--! @version 0.1
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;
--==================================================================================================
--! @brief Packet based FIFO with SDP dual-clock RAM storage
--! @details
--! This entity implements a FIFO that supports packets from an incoming stream to be buffered.
--! Block RAM is used as main storage for resource optimization.
--! This Packet FIFO supports packet width adaptation using simple dual port RAM primitives.
--! Packets can be dropped from the FIFO by the write side asserting the `snk_drop_i` signal.
--! The drop signal is captured when asserted in a packet and the FIFO will hold its `snk_ready_o`
--! HIGH until `snk_eop_i` and s`snk_valid_i` are asserted.
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity packet_cc_ram_fifo is
  generic (
    g_DATA_WIDTH       : natural    := 32;
    g_MAX_PACKET_BYTES : natural;
    g_NUM_PACKETS      : natural;
    g_SNK_DATA_WIDTH   : natural    := g_DATA_WIDTH;
    g_SRC_DATA_WIDTH   : natural    := g_DATA_WIDTH;
    g_IMPL_STYLE       : compiler_t := get_compiler
  );
  port (
    reset_i     : in    std_logic;
    snk_clk_i   : in    std_logic;
    src_clk_i   : in    std_logic;
    --! ports
    snk_sop_i   : in    std_logic;
    snk_eop_i   : in    std_logic;
    snk_data_i  : in    std_logic_vector(g_SNK_DATA_WIDTH - 1 downto 0);
    snk_empty_i : in    unsigned(log2ceil(g_SNK_DATA_WIDTH / 8) - 1 downto 0);
    snk_valid_i : in    std_logic;
    snk_ready_o : out   std_logic;
    snk_drop_i  : in    std_logic;
    --
    src_sop_o   : out   std_logic;
    src_eop_o   : out   std_logic;
    src_data_o  : out   std_logic_vector(g_SRC_DATA_WIDTH - 1 downto 0);
    src_empty_o : out   unsigned(log2ceil(g_SRC_DATA_WIDTH / 8) - 1 downto 0);
    src_size_o  : out   unsigned(log2ceil(g_MAX_PACKET_BYTES * g_NUM_PACKETS) - 1 downto 0);
    src_ready_i : in    std_logic;
    src_valid_o : out   std_logic
  );
end entity packet_cc_ram_fifo;

architecture rtl of packet_cc_ram_fifo is

  -- FIFO buffer size to absorb ram storage latency
  constant c_LAT_FIFO_WORDS : natural := 4;

  -- ratio for mixed width ports
  constant c_RATIO : natural := maximum(g_SNK_DATA_WIDTH, g_SRC_DATA_WIDTH) /
    minimum(g_SNK_DATA_WIDTH, g_SRC_DATA_WIDTH);

  -- mixed width calculations
  constant c_NUM_WORDS : positive := g_MAX_PACKET_BYTES * g_NUM_PACKETS /
    (maximum(g_SNK_DATA_WIDTH, g_SRC_DATA_WIDTH) / 8);
  constant c_SNK_WORDS : natural  :=
  (
    maximum(g_SNK_DATA_WIDTH,
             g_SRC_DATA_WIDTH)
    * c_NUM_WORDS / g_SNK_DATA_WIDTH
  );
  constant c_SRC_WORDS : natural  :=
  (
    maximum(g_SNK_DATA_WIDTH,
             g_SRC_DATA_WIDTH)
    * c_NUM_WORDS / g_SRC_DATA_WIDTH
  );

  -- write side types
  subtype avst_snk_t is avst_master_t(
    data(g_SNK_DATA_WIDTH - 1 downto 0),
    empty(log2ceil(g_SNK_DATA_WIDTH / 8) - 1 downto 0)
  );

  type snk_fsm_t is (S_IDLE, S_PACKET, S_SIZE, S_DROP);

  type snk_sig_t is record
    state      : snk_fsm_t;
    ready      : std_logic;
    level      : natural range 0 to c_SNK_WORDS;
    size       : natural range 0 to g_MAX_PACKET_BYTES * g_NUM_PACKETS;
    addr       : natural range 0 to c_SNK_WORDS - 1;
    start      : natural range 0 to c_SNK_WORDS - 1;
    words      : natural range 0 to c_SNK_WORDS;
    enable     : std_logic;
    size_write : std_logic;
    wrq        : unsigned(src_size_o'length - 1 downto 0);
  end record snk_sig_t;

  -- read side types
  subtype avst_src_t is avst_master_t(
    data(g_SRC_DATA_WIDTH - 1 downto 0),
    empty(log2ceil(g_SRC_DATA_WIDTH / 8) - 1 downto 0)
  );

  type src_fsm_t is (S_IDLE, S_PACKET);

  type src_sig_t is record
    state  : src_fsm_t;
    rdram  : std_logic;
    rdpipe : std_logic;
    rdsize : std_logic;
    size   : natural range 0 to g_MAX_PACKET_BYTES * g_NUM_PACKETS;
    empty  : natural range 0 to g_SRC_DATA_WIDTH / 8 - 1;
    words  : natural range 0 to c_SRC_WORDS;
    rdcnt  : natural range 0 to c_SRC_WORDS;
    outcnt : natural range 0 to c_SRC_WORDS;
    addr   : natural range 0 to c_SRC_WORDS - 1;
    avst   : avst_src_t;
  end record src_sig_t;

  -- records for scoped component wiring
  type ram_ctrl_t is record
    wren   : std_logic;
    rden   : std_logic;
    wraddr : unsigned(log2ceil(c_SNK_WORDS) - 1 downto 0);
    rdaddr : unsigned(log2ceil(c_SRC_WORDS) - 1 downto 0);
    wrdata : std_logic_vector(g_SNK_DATA_WIDTH - 1 downto 0);
    rddata : std_logic_vector(g_SRC_DATA_WIDTH - 1 downto 0);
  end record ram_ctrl_t;

  type fifo_t is record
    wrreq     : std_logic;
    rdreq     : std_logic;
    wrempty   : std_logic;
    rdempty   : std_logic;
    wrfull    : std_logic;
    rdfull    : std_logic;
    wrq_valid : std_logic;
    wrusedw   : unsigned(log2ceil(g_NUM_PACKETS) - 1 downto 0);
    rdusedw   : unsigned(log2ceil(g_NUM_PACKETS) - 1 downto 0);
    data      : unsigned(src_size_o'length - 1 downto 0);
    wrq       : unsigned(src_size_o'length - 1 downto 0);
    q         : unsigned(src_size_o'length - 1 downto 0);
    -- extra
    almost_full : std_logic;
  end record fifo_t;

  -- type related constants
  constant c_AVST_INIT : avst_src_t :=
  (
    valid => '0',
    sop   => '0',
    eop   => '0',
    empty => (others => '0'),
    data  => (others => '0')
  );

  constant c_SNK_SIG_INIT : snk_sig_t :=
  (
    state      => S_IDLE,
    ready      => '0',
    level      => 0,
    size       => 0,
    addr       => 0,
    start      => 0,
    words      => 0,
    enable     => '0',
    size_write => '0',
    wrq        => (others => '0')
  );

  constant c_SRC_SIG_INIT : src_sig_t :=
  (
    state  => S_IDLE,
    rdram  => '0',
    rdpipe => '0',
    rdsize => '0',
    size   => 0,
    rdcnt  => 0,
    outcnt => 0,
    words  => 0,
    empty  => 0,
    addr   => 0,
    avst   => c_AVST_INIT
  );
  ---------------------------
  -- signals
  --------------------------
  -- resets
  signal reset_snk        : std_logic;
  signal reset_src        : std_logic;
  -- control records
  signal ram              : ram_ctrl_t;
  signal size             : fifo_t;
  -- FSMs
  signal snk_rreg         : snk_sig_t := c_SNK_SIG_INIT;
  signal snk_rcmb         : snk_sig_t;
  signal src_rreg         : src_sig_t := c_SRC_SIG_INIT;
  signal src_rcmb         : src_sig_t;
  -- skid buffer elements
  signal skid             : avst_snk_t;
  signal skid_drop        : std_logic;
  -- ram and latency fifo elements
  signal rdram_reg        : std_logic;
  signal pipe_data        : std_logic_vector(g_SRC_DATA_WIDTH - 1 downto 0);
  signal pipe_empty       : std_logic;
  signal pipe_full        : std_logic;
  signal pipe_usedw       : unsigned(log2ceil(c_LAT_FIFO_WORDS) downto 0);

begin

  -- reset synchros

  snk_reset_inst : entity colibri.synchro_reset
    port map (
      clk_i   => snk_clk_i,
      reset_i => reset_i,
      reset_o => reset_snk
    );

  src_reset_inst : entity colibri.synchro_reset
    port map (
      clk_i   => src_clk_i,
      reset_i => reset_i,
      reset_o => reset_src
    );

  -- avst buffer

  skid_buffer_inst : entity colibri.skid_buffer
    generic map (
      g_DATA_WIDTH => g_SNK_DATA_WIDTH
    )
    port map (
      clk_i       => snk_clk_i,
      reset_i     => reset_snk,
      snk_data_i  => snk_data_i,
      snk_empty_i => snk_empty_i,
      snk_keep_i  => (others => '0'),
      snk_sop_i   => snk_sop_i,
      snk_eop_i   => snk_eop_i,
      snk_valid_i => snk_valid_i,
      snk_ready_o => snk_ready_o,
      src_data_o  => skid.data,
      src_empty_o => skid.empty,
      src_keep_o  => open,
      src_sop_o   => skid.sop,
      src_eop_o   => skid.eop,
      src_valid_o => skid.valid,
      src_ready_i => snk_rcmb.ready
    );

  drop_buf_inst : entity colibri.stream_buffer
    generic map (
      g_DATA_WIDTH        => 1,
      g_REGISTER_DATAPATH => false
    )
    port map (
      reset_i       => reset_snk,
      clk_i         => snk_clk_i,
      snk_data_i(0) => snk_drop_i,
      snk_valid_i   => snk_valid_i,
      snk_ready_o   => open,
      src_data_o(0) => skid_drop,
      src_ready_i   => snk_rcmb.ready,
      src_valid_o   => open
    );

  -- main storage as block ram
  main_ram_inst : entity colibri.simple_dpram
    generic map (
      g_A_DATA_WIDTH => g_SNK_DATA_WIDTH,
      g_B_DATA_WIDTH => g_SRC_DATA_WIDTH,
      g_N_WORDS      => c_NUM_WORDS,
      g_A_ADDR_WIDTH => log2ceil(c_SNK_WORDS),
      g_B_ADDR_WIDTH => log2ceil(c_SRC_WORDS),
      g_REGISTER_OUT => true,
      g_IMPL_STYLE   => g_IMPL_STYLE
    )
    port map (
      wrclk_i  => snk_clk_i,
      wren_i   => ram.wren,
      wraddr_i => ram.wraddr,
      wrdata_i => ram.wrdata,
      rdclk_i  => src_clk_i,
      rden_i   => ram.rden,
      rdaddr_i => ram.rdaddr,
      rddata_o => ram.rddata
    );

  -- fifo to absorb ram read latency
  rdram_reg <= src_rreg.rdram when rising_edge(src_clk_i);

  latency_fifo_inst : entity colibri.fifo
    generic map (
      g_NUM_WORDS   => c_LAT_FIFO_WORDS,
      g_INPUT_WIDTH => g_SRC_DATA_WIDTH,
      g_ENABLE_FWFT => true
    )
    port map (
      clk_i   => src_clk_i,
      reset_i => reset_src,
      data_i  => ram.rddata,
      wrreq_i => rdram_reg,
      rdreq_i => src_rcmb.rdpipe,
      q_o     => pipe_data,
      usedw_o => pipe_usedw,
      empty_o => pipe_empty,
      full_o  => pipe_full
    );

  -- cdc fifo to pass size information between wr and rd side
  size_fifo_inst : entity colibri.cc_fifo
    generic map (
      g_NUM_WORDS   => g_NUM_PACKETS,
      g_INPUT_WIDTH => src_size_o'length,
      g_ENABLE_FWFT => true,
      g_PEEK_NEXT   => true
    )
    port map (
      reset_i         => reset_i,
      wrclk_i         => snk_clk_i,
      rdclk_i         => src_clk_i,
      data_i          => std_logic_vector(size.data),
      wrreq_i         => size.wrreq,
      rdreq_i         => size.rdreq,
      unsigned(q_o)   => size.q,
      wrusedw_o       => size.wrusedw,
      rdusedw_o       => size.rdusedw,
      wrempty_o       => size.wrempty,
      wrfull_o        => size.wrfull,
      rdempty_o       => size.rdempty,
      rdfull_o        => size.rdfull,
      unsigned(wrq_o) => size.wrq,
      wrq_valid_o     => size.wrq_valid
    );

  size.almost_full <= '0' when size.wrusedw < g_NUM_PACKETS - 2 else
                      '1';
  --====================================================
  --      Write Side Logic
  --====================================================
  snk_rreg <= snk_rcmb when rising_edge(snk_clk_i);

  proc_write_fsm : process (all) is

    variable v_int : snk_sig_t;

  begin

    v_int            := snk_rreg;
    v_int.ready      := '0';
    v_int.size_write := '0';

    if (size.wrq_valid) then
      v_int.wrq    := size.wrq;
      v_int.words  := to_integer(div_ceil(size.wrq, g_SNK_DATA_WIDTH / 8));
      v_int.enable := '1';
      if (snk_rreg.enable = '1' and snk_rreg.wrq /= size.wrq) then
        v_int.level := snk_rreg.level - snk_rreg.words;
      end if;
    end if;

    case snk_rreg.state is

      when S_IDLE =>
        -- storage not full, there is space to write
        if (snk_rreg.level /= c_SNK_WORDS) then
          -- valid input (start)
          if (skid.valid and skid.sop and not skid_drop) then
            v_int.ready := '1';
            v_int.start := snk_rreg.addr; -- save start ptr for drop purposes

            -- update pointer and occupancy
            if (snk_rreg.addr /= c_SNK_WORDS - 1) then
              v_int.addr := snk_rreg.addr + 1;
            else
              v_int.addr := 0;
            end if;
            v_int.level := v_int.level + 1;

            -- multi word packet
            if (not skid.eop) then
              v_int.size  :=(g_SNK_DATA_WIDTH / 8);
              v_int.state := S_PACKET;
            else
              -- single word packet
              v_int.size :=(g_SNK_DATA_WIDTH / 8) - to_integer(skid.empty);
              -- advance pointer if mixed width
              if (c_RATIO > 1 and g_SRC_DATA_WIDTH > g_SNK_DATA_WIDTH) then
                if (snk_rreg.addr < c_SNK_WORDS - c_RATIO) then
                  v_int.addr := c_RATIO * div_ceil(snk_rreg.addr, c_RATIO);
                else
                  v_int.addr := 0;
                end if;
              end if;
              -- prevent writing to a full fifo
              if (not size.almost_full) then
                v_int.size_write := '1';
              else
                v_int.state := S_SIZE;
              end if;
            end if;
          elsif (skid.valid) then -- drop any malformed packet or if drop is asserted
            v_int.ready := '1';
            -- go to drop if in the middle of a packet
            if (not skid.eop) then
              v_int.state := S_DROP;
            end if;
          end if;
        end if;

      when S_PACKET =>
        -- storage not full, there is space to write
        if (snk_rreg.level /= c_SNK_WORDS) then
          if (skid_drop or snk_drop_i) then -- sample drop even when not ready
            -- drop the current packet and reset the address and lower occupancy
            v_int.addr  := snk_rreg.start;
            v_int.level := v_int.level - (snk_rreg.size * 8) / g_SNK_DATA_WIDTH;
            v_int.ready := '1';
            if (skid.eop) then
              v_int.state := S_IDLE;
            else
              v_int.state := S_DROP;
            end if;
          -- valid packet data
          elsif (skid.valid) then
            v_int.ready := '1';
            -- update pointer and occupancy
            if (snk_rreg.addr /= c_SNK_WORDS - 1) then
              v_int.addr := snk_rreg.addr + 1;
            else
              v_int.addr := 0;
            end if;
            v_int.level := v_int.level + 1;

            -- multi word packet
            if (not skid.eop) then
              v_int.size  := snk_rreg.size + (g_SNK_DATA_WIDTH / 8);
              v_int.state := S_PACKET;
            else
              v_int.size := snk_rreg.size + (g_SNK_DATA_WIDTH / 8) - to_integer(skid.empty);
              -- advance pointer if mixed width
              if (c_RATIO > 1 and g_SRC_DATA_WIDTH > g_SNK_DATA_WIDTH) then
                if (snk_rreg.addr < c_SNK_WORDS - c_RATIO) then
                  v_int.addr := c_RATIO * ((snk_rreg.addr / c_RATIO) + 1);
                else
                  v_int.addr := 0;
                end if;
              end if;
              if (not size.wrfull) then
                v_int.size_write := '1';
                v_int.state      := S_IDLE;
              else
                v_int.state := S_SIZE;
              end if;
            end if;
          end if;
        else
          -- single packet too big for storage (DROP)
          if (size.wrempty) then
            -- drop the current packet and reset the address and lower occupancy
            v_int.addr  := snk_rreg.start;
            v_int.level := v_int.level - (snk_rreg.size * 8) / g_SNK_DATA_WIDTH;
            if (skid.eop) then
              v_int.state := S_IDLE;
            else
              v_int.state := S_DROP;
            end if;
          end if;
        end if;

      when S_SIZE =>
        -- wait for packet to be read if size fifo is full
        if (not size.wrfull) then
          v_int.size_write := '1';
          v_int.state      := S_IDLE;
        end if;

      when S_DROP =>
        -- flush all remaining packet words
        v_int.ready := '1';

        if (skid.valid and skid.eop) then
          v_int.state := S_IDLE;
        end if;

    end case;

    if (reset_i = '1') then
      v_int := c_SNK_SIG_INIT;
    end if;

    snk_rcmb <= v_int;

  end process proc_write_fsm;

  ram.wren   <= skid.valid and snk_rcmb.ready;
  ram.wraddr <= to_unsigned(snk_rreg.addr, log2ceil(c_SNK_WORDS));
  ram.wrdata <= skid.data;
  size.wrreq <= snk_rreg.size_write;
  size.data  <= to_unsigned(snk_rreg.size, src_size_o'length);

  --===================================================
  --      Read Side Logic
  --===================================================

  proc_read_fsm : process (all) is

    variable v_int : src_sig_t;

  begin

    v_int        := src_rreg;
    v_int.rdsize := '0';
    v_int.rdram  := '0';
    v_int.rdpipe := '0';

    if (src_ready_i) then
      v_int.avst := c_AVST_INIT;
    end if;

    case src_rreg.state is

      when S_IDLE =>
        -- new packet in main storage fifo and output buffer empty
        if ((not size.rdempty) and  (not v_int.avst.valid)) then
          v_int.size   := TO_INTEGER(size.q);
          v_int.words  := TO_INTEGER(div_ceil(size.q, g_SRC_DATA_WIDTH / 8));
          v_int.rdcnt  := 0;
          v_int.outcnt := 0;
          -- align address pointer if mixed width
          if (c_RATIO > 1 and g_SNK_DATA_WIDTH > g_SRC_DATA_WIDTH) then
            if (src_rreg.addr <= c_SRC_WORDS - c_RATIO) then
              v_int.addr := c_RATIO * div_ceil(src_rreg.addr, c_RATIO);
            else
              v_int.addr := 0;
            end if;
          end if;
          v_int.state := S_PACKET;
        end if;

      when S_PACKET =>

        -- separate ram addressing from data output
        -- if space in latency fifo, read from ram
        if (pipe_usedw < c_LAT_FIFO_WORDS / 2) then
          if (v_int.rdcnt = 0) then
            -- calculate empty packet size
            v_int.empty :=  (g_SRC_DATA_WIDTH / 8) * src_rreg.words - src_rreg.size;
          end if;
          if (src_rreg.rdcnt < src_rreg.words) then
            v_int.rdram := '1'; -- read enable
            -- advance pointer
            if (src_rreg.addr < c_SRC_WORDS - 1) then
              v_int.addr := src_rreg.addr + 1;
            else
              v_int.addr := 0;
            end if;
            v_int.rdcnt := src_rreg.rdcnt + 1;
            if (src_rreg.rdcnt = src_rreg.words - 1) then
              v_int.rdsize := '1';
            end if;
          end if;
        end if;

        -- if data in latency fifo and no backpressure
        if (not v_int.avst.valid and not pipe_empty) then
          v_int.avst := c_AVST_INIT;
          -- start of packet
          if (src_rreg.outcnt = 0) then
            v_int.avst.sop := '1';
          end if;
          -- read from latency fifo
          v_int.rdpipe     := '1';
          v_int.avst.valid := '1';
          v_int.avst.data  := pipe_data;
          v_int.outcnt     := src_rreg.outcnt + 1;
          if (src_rreg.outcnt = src_rreg.words - 1) then
            -- packet complete
            v_int.avst.eop   := '1';
            v_int.avst.empty := to_unsigned(v_int.empty, src_empty_o'length);
            v_int.state      := S_IDLE;
          end if;
        end if;

    end case;

    src_rcmb <= v_int;

  end process proc_read_fsm;

  src_rreg <= src_rcmb when rising_edge(src_clk_i);

  ram.rdaddr <= to_unsigned(src_rreg.addr, log2ceil(c_SRC_WORDS));
  ram.rden   <= src_rcmb.rdram;

  size.rdreq  <= src_rreg.rdsize;
  src_sop_o   <= src_rreg.avst.sop;
  src_eop_o   <= src_rreg.avst.eop;
  src_data_o  <= src_rreg.avst.data;
  src_empty_o <= src_rreg.avst.empty;
  src_size_o  <= to_unsigned(src_rreg.size, src_size_o'length);
  src_valid_o <= src_rreg.avst.valid;

end architecture rtl;
