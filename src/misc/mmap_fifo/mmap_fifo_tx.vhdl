--! @file mmap_fifo_tx.vhdl
--! @brief Memory Mapped FIFO to Stream
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

use work.txfifo_csr_pkg.all;

--==================================================================================================
--! @brief Memory Mapped FIFO to Stream
--! @details
--! This entity implements a memory mapped interface to a FIFO, allowing access to streams.
--! How to trigger an TX operation:
--! - Enable Interrupts (e.g. TX complete).
--! - Write destination ID (channel). [optional]
--! - Write data to data register.
--! - Write packet size in bytes to initiate transfer.
--! - Wait for interrupt to indicate TX completion
--!
--! Interrupt register also implements error management for:
--! - Writing to a full FIFO
--! - Requesting a larger TX than available in the FIFO
--!
--! Changelog:
--! - 0.2 add support for RAM based FIFO
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity mmap_fifo_tx is
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
    --! @virtualbus Avalon-ST @dir out source
    src_ready_i : in    std_logic;
    src_valid_o : out   std_logic;
    src_sop_o   : out   std_logic;
    src_eop_o   : out   std_logic;
    src_empty_o : out   unsigned(log2ceil(g_STREAM_DATA_WIDTH / 8) - 1 downto 0);
    src_data_o  : out   std_logic_vector(g_STREAM_DATA_WIDTH - 1 downto 0);
    src_chan_o  : out   unsigned(log2ceil(g_NUM_CH) - 1 downto 0);
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
end entity mmap_fifo_tx;

architecture rtl of mmap_fifo_tx is

  constant c_MAX_WORD_BYTES : integer := MAXIMUM(g_WB_DATA_WIDTH, g_STREAM_DATA_WIDTH) / 8;
  constant c_MAX_BYTES      : integer := g_NUM_WORDS * c_MAX_WORD_BYTES;

  -- CSR Handling
  signal wb_rack     : std_logic;
  signal wb_rack_reg : std_logic;
  signal wb_odat     : std_logic_vector(g_WB_DATA_WIDTH - 1 downto 0);
  signal wb_wack     : std_logic;
  signal wb_rerr     : std_logic;
  signal wb_werr     : std_logic;

  signal csr_s2m : txfifo_csr_in_t;
  signal csr_m2s : txfifo_csr_out_t;

  signal wb_reset : std_logic;

  -- AVST record
  subtype avst_t is avst_master_t(
    data(g_STREAM_DATA_WIDTH - 1 downto 0),
    empty(log2ceil(g_STREAM_DATA_WIDTH / 8) - 1 downto 0)
  );

  constant c_AVST_INIT : avst_t :=
  (
    valid => '0',
    sop   => '0',
    eop   => '0',
    empty => (others => '0'),
    data  => (others => '0')
  );

  type fsm_t is (S_IDLE, S_SOP, S_PACKET, S_FLUSH, S_ERROR);

  type fifo_stat_t is record
    empty : std_logic;
    full  : std_logic;
    usedw : unsigned(log2ceil(g_NUM_WORDS) - 1 downto 0);
  end record fifo_stat_t;

  type sig_t is record
    state : fsm_t;
    avst  : avst_t;
    ready : std_logic;
    done  : std_logic;
    empty : integer range 0 to (g_STREAM_DATA_WIDTH / 8 - 1);
    size  : integer range 0 to c_MAX_BYTES;
    chan  : integer range 0 to g_NUM_CH - 1;
    words : integer range 0 to c_MAX_BYTES / (g_STREAM_DATA_WIDTH / 8);
  end record sig_t;

  constant c_SIG_INIT : sig_t :=
  (
    state => S_IDLE,
    avst  => c_AVST_INIT,
    ready => '0',
    done  => '0',
    empty => 0,
    size  => 0,
    chan  => 0,
    words => 0
  );

  signal txwrreq   : std_logic;
  signal txdata    : std_logic_vector(g_STREAM_DATA_WIDTH - 1 downto 0);
  -- CDC tx len
  signal txlen_upd : std_logic;
  signal txlen_ok  : std_logic;
  signal wrlen     : unsigned(log2ceil(c_MAX_BYTES) downto 0);
  signal txlen     : unsigned(log2ceil(c_MAX_BYTES) downto 0);
  signal txchan    : unsigned(log2ceil(g_NUM_CH) - 1 downto 0);
  signal init_tx   : std_logic;

  signal wb_txstat : fifo_stat_t;
  signal txstat    : fifo_stat_t;
  signal txreset   : std_logic;

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

  ------------------------------------------------------
  --              Memory Mapped Registers
  ------------------------------------------------------
  wb_ack_o <= (wb_rack_reg or wb_wack);
  wb_err_o <= (wb_rerr or wb_werr);

  txfifo_csr_inst : entity work.txfifo_csr
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
  --              Transmit FIFO
  ------------------------------------------------------
  gen_ram_impl : if g_USE_BLOCK_RAM generate

    tx_fifo_inst : entity colibri.cc_ram_fifo
      generic map (
        g_NUM_WORDS    => g_NUM_WORDS,
        g_INPUT_WIDTH  => g_WB_DATA_WIDTH,
        g_OUTPUT_WIDTH => g_STREAM_DATA_WIDTH,
        g_ENABLE_FWFT  => true,
        g_IMPL_STYLE   => g_IMPL_STYLE
      )
      port map (
        reset_i   => txreset,
        wrclk_i   => wb_clk_i,
        rdclk_i   => clk_i,
        data_i    => csr_m2s.write.data.value,
        wrreq_i   => txwrreq,
        rdreq_i   => rcmb.ready,
        q_o       => txdata,
        wrusedw_o => wb_txstat.usedw,
        rdusedw_o => txstat.usedw,
        wrempty_o => wb_txstat.empty,
        wrfull_o  => wb_txstat.full,
        rdempty_o => txstat.empty,
        rdfull_o  => txstat.full
      );

  else generate

    tx_fifo_inst : entity colibri.cc_fifo
      generic map (
        g_NUM_WORDS    => g_NUM_WORDS,
        g_INPUT_WIDTH  => g_WB_DATA_WIDTH,
        g_OUTPUT_WIDTH => g_STREAM_DATA_WIDTH,
        g_ENABLE_FWFT  => true
      )
      port map (
        reset_i   => txreset,
        wrclk_i   => wb_clk_i,
        rdclk_i   => clk_i,
        data_i    => csr_m2s.write.data.value,
        wrreq_i   => txwrreq,
        rdreq_i   => rcmb.ready,
        q_o       => txdata,
        wrusedw_o => wb_txstat.usedw,
        rdusedw_o => txstat.usedw,
        wrempty_o => wb_txstat.empty,
        wrfull_o  => wb_txstat.full,
        rdempty_o => txstat.empty,
        rdfull_o  => txstat.full
      );

  end generate gen_ram_impl;

  txwrreq                   <= csr_m2s.write.data.swmod when rising_edge(wb_clk_i);
  txlen_upd                 <= csr_m2s.length.bytes.swmod when rising_edge(wb_clk_i);
  csr_s2m.isr.wrf.next_q    <= wb_txstat.full and txwrreq;
  csr_s2m.fill.usedw.next_q <= std_logic_vector(resize(wb_txstat.usedw, g_WB_DATA_WIDTH));

  txreset <= csr_m2s.ctrl.rst.value or wb_reset;

  ----------------------------------------------------
  -- count written length and issue interrupt if error
  ----------------------------------------------------
  proc_count_len : process (wb_clk_i) is
  begin

    if rising_edge(wb_clk_i) then
      txlen_ok <= '0';
      if (txreset = '1' or txlen_upd = '1') then
        wrlen                  <= (others => '0');
        csr_s2m.isr.tle.next_q <= '0';
        if (wrlen < resize(unsigned(csr_m2s.length.bytes.value), txlen'length)) then
          csr_s2m.isr.tle.next_q <= '1';
        else
          txlen_ok <= txlen_upd;
        end if;
      else
        csr_s2m.isr.tle.next_q <= '0';
        if (txwrreq  and not wb_txstat.full) then
          wrlen <= wrlen + (g_WB_DATA_WIDTH / 8);
        end if;
      end if;
    end if;

  end process proc_count_len;

  -- save txlen for CDC in local register
  proc_reg_txlen : process (wb_clk_i) is
  begin

    if rising_edge(wb_clk_i) then
      if (txlen_upd) then
        txlen  <= resize(unsigned(csr_m2s.length.bytes.value), txlen'length);
        txchan <= resize(unsigned(csr_m2s.dst.id.value), txchan'length);
      end if;
    end if;

  end process proc_reg_txlen;

  -- issue start of packet strobe
  txstart_sync_inst : entity colibri.synchro_pulse
    port map (
      src_clk_i => wb_clk_i,
      dst_clk_i => clk_i,
      pulse_i   => txlen_ok,
      pulse_o   => init_tx
    );

  -- issue a tx complete interrupt
  txcomplete_sync_inst : entity colibri.synchro_pulse
    port map (
      src_clk_i => clk_i,
      dst_clk_i => wb_clk_i,
      pulse_i   => rreg.done,
      pulse_o   => csr_s2m.isr.txc.next_q
    );

  --------------------------------------------------------------
  --                      Transmit FSM
  --------------------------------------------------------------

  rreg <= rcmb when rising_edge(clk_i);

  proc_tx_fsm : process (all) is

    variable v_int : sig_t;

  begin

    v_int       := rreg;
    v_int.done  := '0';
    v_int.ready := '0';
    -- acknowledge a read
    if (src_ready_i) then
      v_int.avst := c_AVST_INIT;
    end if;

    case v_int.state is

      when S_IDLE =>
        -- start transfer strobe
        if (init_tx) then
          v_int.size  := to_integer(txlen);
          v_int.chan  := to_integer(txchan);
          v_int.words := div_ceil(v_int.size, g_STREAM_DATA_WIDTH / 8);
          v_int.empty := v_int.words  * (g_STREAM_DATA_WIDTH / 8) - v_int.size;
          v_int.state := S_SOP;
        end if;

      when S_SOP =>

        if (not txstat.empty) then         -- data in the fifo
          if (v_int.avst.valid = '0') then -- output buffer is free
            v_int.ready      := '1';       -- read from fifo
            v_int.avst.valid := '1';
            v_int.avst.sop   := '1';
            v_int.avst.data  := txdata;
            v_int.words      := rreg.words - 1;
            -- multi word packet
            if (rreg.words > 1) then
              v_int.state := S_PACKET;
            else
              -- single word packet
              v_int.avst.eop   := '1';
              v_int.avst.empty := to_unsigned(rreg.empty, src_empty_o'length);
              v_int.state      := S_FLUSH;
            end if;
          end if;
        end if;

      when S_PACKET =>

        if (not txstat.empty) then
          if (not v_int.avst.valid) then
            v_int.ready      := '1';
            v_int.avst.valid := '1';
            v_int.avst.data  := txdata;
            v_int.words      := rreg.words - 1;
            if (rreg.words > 1) then
              v_int.state := S_PACKET;
            else
              -- single word packet
              v_int.avst.eop   := '1';
              v_int.avst.empty := to_unsigned(rreg.empty, src_empty_o'length);
              v_int.state      := S_FLUSH;
            end if;
          end if;
        end if;

      when S_FLUSH =>
        -- wait for sink to ack last word
        if (src_ready_i) then
          v_int.state := S_IDLE;
          v_int.done  := '1';
        end if;

    end case;

    if (reset_i) then
      v_int := c_SIG_INIT;
    end if;

    rcmb <= v_int;

  end process proc_tx_fsm;

  src_valid_o <= rreg.avst.valid;
  src_sop_o   <= rreg.avst.sop;
  src_eop_o   <= rreg.avst.eop;
  src_empty_o <= rreg.avst.empty;
  src_data_o  <= rreg.avst.data;
  src_chan_o  <= to_unsigned(rreg.chan, src_chan_o'length);

end architecture rtl;
