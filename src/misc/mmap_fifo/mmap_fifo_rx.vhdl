--! @file mmap_fifo_rx.vhdl
--! @brief stream to Memory Mapped FIFO
--! @author Alberto Perro
--! @date 26-02-2026 Created
--! @version 0.2
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;

use work.rxfifo_csr_pkg.all;

--==================================================================================================
--! @brief stream to Memory Mapped FIFO
--! @details
--! This entity implements a memory mapped interface to a FIFO, allowing access to streams.
--! How to trigger an RX operation:
--! - Enable Interrupts (e.g. RX complete).
--! - Wait for interrupt to indicate RX completion
--! - Read Source ID (channel). [optional]
--! - Read packet size in bytes. [optional]
--! - Read data from data register.
--!
--! Interrupt register also implements error management for:
--! - Receiving with a full FIFO (requires reset to clear the error)
--! - Reading from an Empty FIFO
--!
--! Changelog:
--! - 0.2 add support for RAM based FIFO
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity mmap_fifo_rx is
  generic (
    --! wishbone address line width
    g_WB_ADDR_WIDTH     : natural    := 32;
    --! wishbone data lines width
    g_WB_DATA_WIDTH     : natural    := 32;
    --! stream width
    g_STREAM_DATA_WIDTH : natural    := g_WB_DATA_WIDTH;
    --! Number of words in FIFOs
    g_NUM_WORDS         : natural;
    --! Number of streaming channels
    g_NUM_CH            : natural    := 4;
    --! Use RAM-based FIFO component
    g_USE_BLOCK_RAM     : boolean    := false;
    --! Implementation style
    g_IMPL_STYLE        : compiler_t := get_compiler
  );
  port (
    reset_i     : in    std_logic;
    clk_i       : in    std_logic;
    --! @virtualbus Avalon-ST @dir in sink
    snk_ready_o : out   std_logic;
    snk_valid_i : in    std_logic;
    snk_sop_i   : in    std_logic;
    snk_eop_i   : in    std_logic;
    snk_empty_i : in    unsigned(log2ceil(g_STREAM_DATA_WIDTH / 8) - 1 downto 0);
    snk_data_i  : in    std_logic_vector(g_STREAM_DATA_WIDTH - 1 downto 0);
    snk_chan_i  : in    unsigned(log2ceil(g_NUM_CH) - 1 downto 0);
    --! @end
    -- wishbone bus interface for CSR
    wb_clk_i    : in    std_logic;
    --! @virtualbus wishbone @dir inout wishbone B4 memory mapped slave
    wb_adr_i    : in    unsigned(g_WB_ADDR_WIDTH - 1 downto 0);
    wb_dat_o    : out   std_logic_vector(g_WB_DATA_WIDTH - 1 downto 0);
    wb_dat_i    : in    std_logic_vector(g_WB_DATA_WIDTH - 1 downto 0);
    wb_we_i     : in    std_logic;
    wb_sel_i    : in    std_logic_vector(g_WB_DATA_WIDTH / 8 - 1 downto 0);
    wb_stb_i    : in    std_logic;
    wb_cyc_i    : in    std_logic;
    wb_ack_o    : out   std_logic;
    wb_err_o    : out   std_logic;
    --! @end
    intr_o      : out   std_logic --! interrupt output
  );
end entity mmap_fifo_rx;

architecture rtl of mmap_fifo_rx is

  constant c_MAX_WORD_BYTES : integer := MAXIMUM(g_WB_DATA_WIDTH, g_STREAM_DATA_WIDTH) / 8;
  constant c_MAX_BYTES      : integer := (g_NUM_WORDS) * c_MAX_WORD_BYTES; -- consider fwft register in fifo

  -- CSR Handling
  signal wb_rack     : std_logic;
  signal wb_rack_reg : std_logic;
  signal wb_odat     : std_logic_vector(g_WB_DATA_WIDTH - 1 downto 0);
  signal wb_wack     : std_logic;
  signal wb_rerr     : std_logic;
  signal wb_werr     : std_logic;

  signal csr_s2m : rxfifo_csr_in_t;
  signal csr_m2s : rxfifo_csr_out_t;

  signal wb_reset : std_logic;

  type fsm_t is (S_IDLE, S_PACKET, S_COMPLETE, S_ERROR);

  type fifo_stat_t is record
    empty : std_logic;
    full  : std_logic;
    usedw : unsigned(log2ceil(g_NUM_WORDS) - 1 downto 0);
  end record fifo_stat_t;

  type sig_t is record
    state : fsm_t;
    ready : std_logic;
    done  : std_logic;
    rwf   : std_logic;
    empty : integer range 0 to (g_STREAM_DATA_WIDTH / 8 - 1);
    size  : integer range 0 to c_MAX_BYTES;
    chan  : integer range 0 to g_NUM_CH - 1;
  end record sig_t;

  constant c_SIG_INIT : sig_t :=
  (
    state => S_IDLE,
    ready => '0',
    done  => '0',
    rwf   => '0',
    empty => 0,
    size  => 0,
    chan  => 0
  );

  signal wrreq  : std_logic;
  signal rxrreq : std_logic;
  signal rxdata : std_logic_vector(g_STREAM_DATA_WIDTH - 1 downto 0);
  -- CDC rx len
  signal rxlen  : unsigned(log2ceil(c_MAX_BYTES) downto 0);
  signal rxchan : unsigned(log2ceil(g_NUM_CH) - 1 downto 0);
  signal rxdone : std_logic;

  signal wb_rxstat  : fifo_stat_t;
  signal rxstat     : fifo_stat_t;
  signal rxreset    : std_logic;
  signal fifo_reset : std_logic;

  signal rreg : sig_t;
  signal rcmb : sig_t;

begin

  ------------------------------------------------------
  --              RESET Synchronizer
  ------------------------------------------------------
  synchro_reset_inst : entity work.synchro_reset
    port map (
      clk_i   => wb_clk_i,
      reset_i => reset_i,
      reset_o => wb_reset
    );

  synchro_wbreset_inst : entity work.synchro_reset
    port map (
      clk_i   => clk_i,
      reset_i => csr_m2s.ctrl.rst.value,
      reset_o => fifo_reset
    );

  ------------------------------------------------------
  --              Memory Mapped Registers
  ------------------------------------------------------
  wb_ack_o <= (wb_rack_reg or wb_wack);
  wb_err_o <= (wb_rerr or wb_werr);

  rxfifo_csr_inst : entity work.rxfifo_csr
    port map (
      clk                  => wb_clk_i,
      rst                  => wb_reset,
      s_cpuif_req          => wb_stb_i,
      s_cpuif_req_is_wr    => wb_we_i,
      s_cpuif_addr         => std_logic_vector(wb_adr_i),
      s_cpuif_wr_data      => wb_dat_i,
      s_cpuif_wr_biten     => (others => '1'),
      s_cpuif_req_stall_wr => open,
      s_cpuif_req_stall_rd => open,
      s_cpuif_rd_ack       => wb_rack,
      s_cpuif_rd_err       => wb_rerr,
      s_cpuif_rd_data      => wb_odat,
      s_cpuif_wr_ack       => wb_wack,
      s_cpuif_wr_err       => wb_werr,
      hwif_in              => csr_s2m,
      hwif_out             => csr_m2s
    );

  wb_rack_reg <= wb_rack when falling_edge(wb_clk_i);
  wb_dat_o    <= wb_odat when falling_edge(wb_clk_i);
  intr_o      <= csr_m2s.isr.intr;

  ------------------------------------------------------
  --              Receive FIFO
  ------------------------------------------------------
  gen_ram_fifo : if g_USE_BLOCK_RAM generate

    rx_fifo_inst : entity colibri.cc_ram_fifo
      generic map (
        g_NUM_WORDS    => g_NUM_WORDS,
        g_INPUT_WIDTH  => g_STREAM_DATA_WIDTH,
        g_OUTPUT_WIDTH => g_WB_DATA_WIDTH,
        g_ENABLE_FWFT  => true,
        g_IMPL_STYLE   => g_IMPL_STYLE
      )
      port map (
        reset_i   => rxreset,
        wrclk_i   => clk_i,
        rdclk_i   => wb_clk_i,
        data_i    => snk_data_i,
        wrreq_i   => wrreq,
        rdreq_i   => rxrreq,
        q_o       => rxdata,
        wrusedw_o => rxstat.usedw,
        rdusedw_o => wb_rxstat.usedw,
        wrempty_o => rxstat.empty,
        wrfull_o  => rxstat.full,
        rdempty_o => wb_rxstat.empty,
        rdfull_o  => wb_rxstat.full
      );

  else generate

    rx_fifo_inst : entity colibri.cc_fifo
      generic map (
        g_NUM_WORDS    => g_NUM_WORDS,
        g_INPUT_WIDTH  => g_STREAM_DATA_WIDTH,
        g_OUTPUT_WIDTH => g_WB_DATA_WIDTH,
        g_ENABLE_FWFT  => true
      )
      port map (
        reset_i   => rxreset,
        wrclk_i   => clk_i,
        rdclk_i   => wb_clk_i,
        data_i    => snk_data_i,
        wrreq_i   => wrreq,
        rdreq_i   => rxrreq,
        q_o       => rxdata,
        wrusedw_o => rxstat.usedw,
        rdusedw_o => wb_rxstat.usedw,
        wrempty_o => rxstat.empty,
        wrfull_o  => rxstat.full,
        rdempty_o => wb_rxstat.empty,
        rdfull_o  => wb_rxstat.full
      );

  end generate gen_ram_fifo;

  wrreq                     <= snk_valid_i and snk_ready_o;
  csr_s2m.read.data.next_q  <= rxdata;
  rxrreq                    <= csr_m2s.read.data.swacc;
  rxreset                   <= fifo_reset or reset_i;
  csr_s2m.fill.usedw.next_q <= std_logic_vector(resize(wb_rxstat.usedw, g_WB_DATA_WIDTH));

  --------------------------------------------------------------
  --                      Receive FSM
  --------------------------------------------------------------

  snk_ready_o <= rcmb.ready;
  rreg        <= rcmb when rising_edge(clk_i);

  proc_tx_fsm : process (all) is

    variable v_int : sig_t;

  begin

    v_int       := rreg;
    v_int.done  := '0';
    v_int.ready := '0';
    v_int.rwf   := '0';

    case v_int.state is

      when S_IDLE =>
        v_int.size := 0;
        -- new packet incoming
        if (snk_sop_i and snk_valid_i) then
          if (not rxstat.full) then -- fifo available
            v_int.ready := '1';
            v_int.chan  := to_integer(snk_chan_i);
            if (snk_eop_i) then
              v_int.size  := (g_STREAM_DATA_WIDTH / 8) - to_integer(snk_empty_i);
              v_int.done  := '1';
              v_int.state := S_COMPLETE;
            else
              v_int.state := S_PACKET;
              v_int.size  := (g_STREAM_DATA_WIDTH / 8);
            end if;
          else                      -- issue interrupt
            v_int.rwf := '1';
          end if;
        end if;

      when S_PACKET =>

        if (snk_valid_i) then
          if (rxstat.usedw < g_NUM_WORDS - 2) then -- fifo available
            v_int.ready := '1';
            if (snk_eop_i) then
              v_int.size  := rreg.size + (g_STREAM_DATA_WIDTH / 8) - to_integer(snk_empty_i);
              v_int.done  := '1';
              v_int.state := S_COMPLETE;
            else
              v_int.size  := rreg.size + (g_STREAM_DATA_WIDTH / 8);
              v_int.state := S_PACKET;
            end if;
          else
            v_int.rwf   := '1';
            v_int.state := S_ERROR;
          end if;
        end if;

      when S_COMPLETE =>
        -- wait for fifo to be empty before reading new packet
        v_int.done := '1';

        if (rxstat.empty) then
          v_int.done  := '0';
          v_int.state := S_IDLE;
        end if;

      when S_ERROR =>
        -- drop any input
        v_int.ready := '1';

        null; -- reset to process new packet

    end case;

    if (rxreset) then
      v_int := c_SIG_INIT;
    end if;

    rcmb <= v_int;

  end process proc_tx_fsm;

  rxdone <= rreg.done when rising_edge(clk_i);
  -- save rx size and channel for CDC in local register
  proc_reg_rxcdc : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rxdone) then
        rxlen  <= to_unsigned(rreg.size, rxlen'length);
        rxchan <= to_unsigned(rreg.chan, rxchan'length);
      end if;
    end if;

  end process proc_reg_rxcdc;

  --------------------------------------------------------------
  --                   Interrupt Handlers
  --------------------------------------------------------------
  -- issue receive complete strobe
  rxdone_sync_inst : entity colibri.synchro_pulse
    port map (
      src_clk_i => clk_i,
      dst_clk_i => wb_clk_i,
      pulse_i   => rxdone,
      pulse_o   => csr_s2m.isr.rxc.next_q
    );

  -- issue write when full interrupt
  rwf_sync_inst : entity colibri.synchro_pulse
    port map (
      src_clk_i => clk_i,
      dst_clk_i => wb_clk_i,
      pulse_i   => rreg.rwf,
      pulse_o   => csr_s2m.isr.rwf.next_q
    );

  csr_s2m.isr.rwe.next_q      <= wb_rxstat.empty and csr_m2s.read.data.swacc;
  csr_s2m.length.bytes.next_q <= std_logic_vector(resize(rxlen, 32)) when csr_s2m.isr.rxc.next_q;
  csr_s2m.src.id.next_q       <= std_logic_vector(resize(rxchan, 32)) when csr_s2m.isr.rxc.next_q;

end architecture rtl;
