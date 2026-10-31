--! @file mmap_fifo.vhdl
--! @brief Memory Mapped Stream FIFO
--! @author Alberto Perro
--! @date 26-02-2026 Created
--! @version 0.1
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;

use work.mmap_fifo_csr_pkg.all;

--==================================================================================================
--! @brief Memory Mapped Stream FIFO
--! @details
--! This entity implements a memory mapped interface to a fifo, allowing access to streams.

-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity mmap_fifo is
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
    rx_intr_o   : out   std_logic; --! rx interrupt output
    tx_intr_o   : out   std_logic  --! tx interrupt output
  );
end entity mmap_fifo;

architecture rtl of mmap_fifo is

  constant c_MAX_WORD_BYTES : integer := MAXIMUM(g_WB_DATA_WIDTH, g_STREAM_DATA_WIDTH) / 8;
  constant c_MAX_BYTES      : integer := g_NUM_WORDS * c_MAX_WORD_BYTES;

  -- CSR Handling
  signal wb_rack : std_logic;
  signal wb_wack : std_logic;
  signal wb_rerr : std_logic;
  signal wb_werr : std_logic;

  signal csr_s2m : mmap_fifo_csr_in_t;
  signal csr_m2s : mmap_fifo_csr_out_t;

  signal wb_reset : std_logic;

  type wb_t is record
    adr  :    unsigned(g_WB_ADDR_WIDTH - 1 downto 0);
    idat :   std_logic_vector(g_WB_DATA_WIDTH - 1 downto 0);
    odat :    std_logic_vector(g_WB_DATA_WIDTH - 1 downto 0);
    we   :    std_logic;
    stb  :    std_logic;
    ack  :   std_logic;
  end record wb_t;

  signal wbtx : wb_t;

  signal wbrx : wb_t;

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
  wb_ack_o <= (wb_rack or wb_wack);
  wb_err_o <= (wb_rerr or wb_werr);

  mmap_fifo_csr_inst : entity work.mmap_fifo_csr
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
      s_cpuif_rd_data      => wb_dat_o,
      s_cpuif_wr_ack       => wb_wack,
      s_cpuif_wr_err       => wb_werr,
      hwif_in              => csr_s2m,
      hwif_out             => csr_m2s
    );

  ------------------------------------------------------
  --              Transmit FIFO
  ------------------------------------------------------

  wbtx.adr           <= resize(unsigned(csr_m2s.tx.addr), g_WB_ADDR_WIDTH);
  wbtx.odat          <= csr_m2s.tx.wr_data;
  wbtx.we            <= csr_m2s.tx.req_is_wr;
  wbtx.stb           <= csr_m2s.tx.req;
  csr_s2m.tx.rd_data <= wbtx.idat;
  csr_s2m.tx.wr_ack  <= wbtx.ack and wbtx.we;
  csr_s2m.tx.rd_ack  <= wbtx.ack and not wbtx.we;

  mmap_fifo_tx_inst : entity work.mmap_fifo_tx
    generic map (
      g_WB_ADDR_WIDTH     => g_WB_ADDR_WIDTH,
      g_WB_DATA_WIDTH     => g_WB_DATA_WIDTH,
      g_STREAM_DATA_WIDTH => g_STREAM_DATA_WIDTH,
      g_NUM_WORDS         => g_NUM_WORDS,
      g_NUM_CH            => g_NUM_CH,
      g_USE_BLOCK_RAM     => g_USE_BLOCK_RAM,
      g_IMPL_STYLE        => g_IMPL_STYLE
    )
    port map (
      reset_i     => reset_i,
      clk_i       => clk_i,
      src_ready_i => src_ready_i,
      src_valid_o => src_valid_o,
      src_sop_o   => src_sop_o,
      src_eop_o   => src_eop_o,
      src_empty_o => src_empty_o,
      src_data_o  => src_data_o,
      src_chan_o  => src_chan_o,
      --
      wb_clk_i => wb_clk_i,
      wb_adr_i => wbtx.adr,
      wb_dat_o => wbtx.idat,
      wb_dat_i => wbtx.odat,
      wb_we_i  => wbtx.we,
      wb_sel_i => (others => '0'),
      wb_stb_i => wbtx.stb,
      wb_cyc_i => '0',
      wb_ack_o => wbtx.ack,
      wb_err_o => open,
      intr_o   => tx_intr_o
    );

  ------------------------------------------------------
  --              Receive FIFO
  ------------------------------------------------------

  wbrx.adr           <= resize(unsigned(csr_m2s.rx.addr), g_WB_ADDR_WIDTH);
  wbrx.odat          <= csr_m2s.rx.wr_data;
  wbrx.we            <= csr_m2s.rx.req_is_wr;
  wbrx.stb           <= csr_m2s.rx.req;
  csr_s2m.rx.rd_data <= wbrx.idat;
  csr_s2m.rx.wr_ack  <= wbrx.ack and wbrx.we;
  csr_s2m.rx.rd_ack  <= wbrx.ack and not wbrx.we;

  mmap_fifo_rx_inst : entity work.mmap_fifo_rx
    generic map (
      g_WB_ADDR_WIDTH     => g_WB_ADDR_WIDTH,
      g_WB_DATA_WIDTH     => g_WB_DATA_WIDTH,
      g_STREAM_DATA_WIDTH => g_STREAM_DATA_WIDTH,
      g_NUM_WORDS         => g_NUM_WORDS,
      g_NUM_CH            => g_NUM_CH,
      g_USE_BLOCK_RAM     => g_USE_BLOCK_RAM,
      g_IMPL_STYLE        => g_IMPL_STYLE
    )
    port map (
      reset_i     => reset_i,
      clk_i       => clk_i,
      snk_ready_o => snk_ready_o,
      snk_valid_i => snk_valid_i,
      snk_sop_i   => snk_sop_i,
      snk_eop_i   => snk_eop_i,
      snk_empty_i => snk_empty_i,
      snk_data_i  => snk_data_i,
      snk_chan_i  => snk_chan_i,
      wb_clk_i    => wb_clk_i,
      wb_adr_i    => wbrx.adr,
      wb_dat_o    => wbrx.idat,
      wb_dat_i    => wbrx.odat,
      wb_we_i     => wbrx.we,
      wb_sel_i    => (others => '0'),
      wb_stb_i    => wbrx.stb,
      wb_cyc_i    => '0',
      wb_ack_o    => wbrx.ack,
      wb_err_o    => open,
      intr_o      => rx_intr_o
    );

end architecture rtl;
