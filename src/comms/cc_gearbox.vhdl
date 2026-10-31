--! @title CDC Gearbox
--! @file cc_gearbox.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 25-06-2024
--! @version 0.3

--! Generic gearbox design with clock domain crossing.
--! Release log:
--! - 0.3: add option to use ram based fifo
--! - 0.2: re-implemented using cc_fifo
--! - 0.1: initial release
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.encoders.all;

entity cc_gearbox is
  generic (

    --! input data width
    g_INPUT_WIDTH   : positive   := 8;
    --! output data width
    g_OUTPUT_WIDTH  : positive   := 10;
    --! buffer size (word width is the largest of g_INPUT_WIDTH and g_OUTPUT_WIDTH)
    g_BUFFER_WORDS  : positive   := 6;
    --! implementation type
    g_USE_BLOCK_RAM : boolean    := false;
    --! implementation style (only used when `g_USE_BLOCK_RAM` is true)
    g_IMPL_STYLE    : compiler_t := get_compiler
  );
  port (
    --! fast clock in input
    snk_clk_i   : in    std_logic;
    --! reset on slow clock
    snk_reset_i : in    std_logic;
    --! slow clock for output
    src_clk_i   : in    std_logic;
    --! @virtualbus aurora_enc @dir in aurora encoded and scrambled data
    snk_data_i  : in    std_logic_vector(g_INPUT_WIDTH - 1 downto 0); --! input data path
    snk_valid_i : in    std_logic;                                    --! input valid
    snk_ready_o : out   std_logic;                                    --! backpressure ready signal
    --! output data path
    src_data_o  : out   std_logic_vector(g_OUTPUT_WIDTH - 1 downto 0);
    src_valid_o : out   std_logic;
    src_ready_i : in    std_logic
  );
end entity cc_gearbox;

architecture rtl of cc_gearbox is

  signal fifo_full  : std_logic;
  signal fifo_empty : std_logic;

begin

  gen_ram_fifo : if g_USE_BLOCK_RAM generate

    cc_fifo_inst : entity colibri.cc_ram_fifo
      generic map (
        g_NUM_WORDS    => g_BUFFER_WORDS,
        g_INPUT_WIDTH  => g_INPUT_WIDTH,
        g_OUTPUT_WIDTH => g_OUTPUT_WIDTH,
        g_ENABLE_FWFT  => true,
        g_IMPL_STYLE   => g_IMPL_STYLE
      )
      port map (
        reset_i => snk_reset_i,
        wrclk_i => snk_clk_i,
        rdclk_i => src_clk_i,

        data_i  => snk_data_i,
        wrreq_i => snk_valid_i,

        rdreq_i => src_ready_i,
        q_o     => src_data_o,

        wrfull_o  => fifo_full,
        rdempty_o => fifo_empty
      );

  else generate

    cc_fifo_inst : entity colibri.cc_fifo
      generic map (
        g_NUM_WORDS    => g_BUFFER_WORDS,
        g_INPUT_WIDTH  => g_INPUT_WIDTH,
        g_OUTPUT_WIDTH => g_OUTPUT_WIDTH,
        g_ENABLE_FWFT  => true
      )
      port map (
        reset_i => snk_reset_i,
        wrclk_i => snk_clk_i,
        rdclk_i => src_clk_i,

        data_i  => snk_data_i,
        wrreq_i => snk_valid_i,

        rdreq_i => src_ready_i,
        q_o     => src_data_o,

        wrfull_o  => fifo_full,
        rdempty_o => fifo_empty
      );

  end generate gen_ram_fifo;

  snk_ready_o <= not fifo_full;
  src_valid_o <= not fifo_empty;

end architecture rtl;
