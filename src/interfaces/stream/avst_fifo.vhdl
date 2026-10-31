--==================================================================================================
--! @brief Avalon-ST FIFO
--!
--!  FIFO wrapper to buffer all Avalon-ST signals in parallel.
--!  The source and sink clocks can be synchronous or asynchronous.
--!  In case of asynchronous clocks, a clock crossing FIFO is generated.
--!
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 27-03-2025 Created
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

entity avst_fifo is
  generic (
    --! Symbol width
    g_SYM_WIDTH    : positive := 8;
    --! Data width in terms of symbols
    g_DATA_SYM     : positive := 16;
    --! FIFO depth in terms of Avalon-ST beats
    g_NUM_BEATS    : positive := 4;
    --! Specify whether sink and source clocks are asynchronous
    g_ASYNC_CLOCKS : boolean  := false
  );
  port (
    --! Clocks and reset
    snk_clk_i   : in    std_logic;
    src_clk_i   : in    std_logic;
    snk_reset_i : in    std_logic;

    --! Avalon stream input
    snk_ready_o : out   std_logic;
    snk_valid_i : in    std_logic;
    snk_sop_i   : in    std_logic;
    snk_eop_i   : in    std_logic;
    snk_empty_i : in    unsigned(maximum(log2ceil(g_DATA_SYM), 1) - 1 downto 0);
    snk_data_i  : in    std_logic_vector(g_SYM_WIDTH * g_DATA_SYM - 1 downto 0);

    --! Avalon stream output
    src_ready_i : in    std_logic;
    src_valid_o : out   std_logic;
    src_sop_o   : out   std_logic;
    src_eop_o   : out   std_logic;
    src_empty_o : out   unsigned(maximum(log2ceil(g_DATA_SYM), 1) - 1 downto 0);
    src_data_o  : out   std_logic_vector(g_SYM_WIDTH * g_DATA_SYM - 1 downto 0)
  );
end entity avst_fifo;

----------------------------------------------------------------------------------------------------

architecture rtl of avst_fifo is

  --! Data/empty bus widths in terms of bits
  constant c_DATA_WIDTH  : positive := g_DATA_SYM * g_SYM_WIDTH;
  constant c_EMPTY_WIDTH : positive := maximum(log2ceil(g_DATA_SYM), 1);
  --! FIFO buffer width (stores data, empty, sop and eop)
  constant c_FIFO_WIDTH  : positive := c_DATA_WIDTH + c_EMPTY_WIDTH + 2;

  signal fifo_in    : std_logic_vector(c_FIFO_WIDTH - 1 downto 0);
  signal fifo_out   : std_logic_vector(c_FIFO_WIDTH - 1 downto 0);
  signal fifo_full  : std_logic;
  signal fifo_empty : std_logic;

begin

  ------------------------------------------------------------------------------
  --! Clock crossing FIFO
  ------------------------------------------------------------------------------
  gen_async_fifo : if g_ASYNC_CLOCKS generate

    cc_fifo_inst : entity colibri.cc_fifo
      generic map (
        g_NUM_WORDS   => g_NUM_BEATS,
        g_INPUT_WIDTH => c_FIFO_WIDTH,
        g_ENABLE_FWFT => true
      )
      port map (
        reset_i => snk_reset_i,
        wrclk_i => snk_clk_i,
        rdclk_i => src_clk_i,

        data_i  => fifo_in,
        wrreq_i => snk_valid_i,
        rdreq_i => src_ready_i,
        q_o     => fifo_out,

        wrusedw_o => open,
        rdusedw_o => open,
        wrempty_o => open,
        wrfull_o  => fifo_full,
        rdempty_o => fifo_empty,
        rdfull_o  => open
      );

  else generate

    fifo_inst : entity work.fifo
      generic map (
        g_NUM_WORDS   => g_NUM_BEATS,
        g_INPUT_WIDTH => c_FIFO_WIDTH,
        g_ENABLE_FWFT => true
      )
      port map (
        clk_i   => snk_clk_i,
        reset_i => snk_reset_i,

        data_i  => fifo_in,
        wrreq_i => snk_valid_i,
        rdreq_i => src_ready_i,
        q_o     => fifo_out,

        usedw_o => open,
        empty_o => fifo_empty,
        full_o  => fifo_full
      );

  end generate gen_async_fifo;

  ------------------------------------------------------------------------------
  --! Port mapping
  ------------------------------------------------------------------------------
  fifo_in     <= snk_sop_i & snk_eop_i & std_logic_vector(snk_empty_i) & snk_data_i;
  snk_ready_o <= not (fifo_full or snk_reset_i);

  proc_src : process (all) is
  begin

    src_valid_o <= not fifo_empty;

    if (fifo_empty) then
      src_sop_o   <= '0';
      src_eop_o   <= '0';
      src_empty_o <= (others => '0');
      src_data_o  <= (others => '0');
    else
      src_sop_o   <= fifo_out(fifo_out'left);
      src_eop_o   <= fifo_out(fifo_out'left - 1);
      src_empty_o <= unsigned(fifo_out(fifo_out'left - 2 downto c_DATA_WIDTH));
      src_data_o  <= fifo_out(c_DATA_WIDTH - 1 downto 0);
    end if;

  end process proc_src;

end architecture rtl;

----------------------------------------------------------------------------------------------------
