--! @brief CDC Streaming Upsizing Gearbox
--! @file cc_gearbox_up.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 25-09-2024
--! @version 0.1
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.encoders.all;
--==================================================================================================
--! @brief CDC Streaming Upsizing Gearbox
--! @details
--! Generic upscaling gearbox for continuous streams with a clock domain crossing.
--! It includes a slip signal to shift the output (1 bit resolution).
--! Based on `gearbox_up` and `cc_fifo`
--! Release log:
--! - 0.1: initial release
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity cc_gearbox_up is
  generic (

    --! input data width
    g_INPUT_WIDTH  : positive := 8;
    --! output data width
    g_OUTPUT_WIDTH : positive := 10;
    --! buffer size (multiples of input width)
    g_BUFFER_WORDS : positive := 6
  );
  port (
    --! fast clock in input
    snk_clk_i   : in    std_logic;
    --! reset on slow clock
    snk_reset_i : in    std_logic;
    --! slow clock for output
    src_clk_i   : in    std_logic;
    slip_i      : in    std_logic;
    --! @virtualbus aurora_enc @dir in aurora encoded and scrambled data
    snk_data_i  : in    std_logic_vector(g_INPUT_WIDTH - 1 downto 0); --! input data path
    snk_valid_i : in    std_logic;                                    --! input valid
    --! output data path
    src_data_o  : out   std_logic_vector(g_OUTPUT_WIDTH - 1 downto 0);
    src_valid_o : out   std_logic
  );
end entity cc_gearbox_up;

architecture rtl of cc_gearbox_up is

  signal wr_slip            : std_logic;
  signal wr_reset, rd_reset : std_logic;
  signal gbx_data           : std_logic_vector(g_OUTPUT_WIDTH - 1 downto 0);
  signal gbx_valid          : std_logic;
  signal fifo_full          : std_logic;
  signal fifo_empty         : std_logic;

begin

  ------------------------------------------------------------------------------
  -- Reset synchronization
  ------------------------------------------------------------------------------
  -- synchronize `reset_i` to write domain
  wr_synchro_reset : entity work.synchro_reset
    generic map (
      g_IN_POLARITY  => '1',
      g_OUT_POLARITY => '1',
      g_DURATION     => 1
    )
    port map (
      clk_i   => snk_clk_i,
      reset_i => snk_reset_i,
      reset_o => wr_reset
    );

  -- synchronize `reset_i` to read domain
  rd_synchro_reset : entity work.synchro_reset
    generic map (
      g_IN_POLARITY  => '1',
      g_OUT_POLARITY => '1',
      g_DURATION     => 1
    )
    port map (
      clk_i   => src_clk_i,
      reset_i => snk_reset_i,
      reset_o => rd_reset
    );

  -- synchronize `slip_i` to write domain
  wr_synchro_slip : entity work.synchro_pulse
    port map (
      src_clk_i => src_clk_i,
      dst_clk_i => snk_clk_i,
      pulse_i   => slip_i,
      pulse_o   => wr_slip
    );

  ------------------------------------------------------------------------------
  -- Input width conversion
  ------------------------------------------------------------------------------
  gearbox_inst : entity colibri.gearbox_up
    generic map (
      g_INPUT_WIDTH  => g_INPUT_WIDTH,
      g_OUTPUT_WIDTH => g_OUTPUT_WIDTH
    )
    port map (
      clk_i       => snk_clk_i,
      reset_i     => wr_reset,
      slip_i      => wr_slip,
      snk_data_i  => snk_data_i,
      snk_valid_i => snk_valid_i,
      src_data_o  => gbx_data,
      src_valid_o => gbx_valid
    );

  cc_fifo_inst : entity work.cc_fifo
    generic map (
      g_NUM_WORDS    => g_BUFFER_WORDS,
      g_INPUT_WIDTH  => g_OUTPUT_WIDTH,
      g_OUTPUT_WIDTH => g_OUTPUT_WIDTH,
      g_ENABLE_FWFT  => true
    )
    port map (
      reset_i => snk_reset_i,
      wrclk_i => snk_clk_i,
      rdclk_i => src_clk_i,

      data_i  => gbx_data,
      wrreq_i => gbx_valid,

      rdreq_i => '1',
      q_o     => src_data_o,

      wrfull_o  => fifo_full,
      rdempty_o => fifo_empty
    );

  src_valid_o <= not fifo_empty;

end architecture rtl;
