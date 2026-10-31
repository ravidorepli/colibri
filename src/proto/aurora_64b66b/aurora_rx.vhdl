--! @file aurora_rx.vhdl
--! @brief Aurora 64b/66b Receiver
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 16-01-2024
--! @version 0.3b
--! @copyright CERN 2026
--==================================================================================================

library ieee;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.poly.all;
  use colibri.types.all;

use work.aurora_const.all;

--==================================================================================================
--! @brief Aurora 64b/66b Receiver
--! @details
--! This entity implements a simplex, multi-lane Aurora 64b/66b Receiver Chain (PMA/PCS).
--! Internal structure:
--!
--!  GEARBOX  ->  DESCRAMBLER -> BIT_SHIFT_FSM -> CHANNEL_BONDING -> DECODER
--!

--! changelog:
--! - 0.1 first release
--! - 0.2 add sub-entity register control in generics
--! - 0.3 add multi-lane support
--! - 0.3b: update to lhcb vhdl style guideline

-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity aurora_rx is
  generic (

    --! Multi Lane Support
    g_N_LANES             : positive := 1;
    --! Lane width in bits
    g_LANE_WIDTH          : positive := 32;
    --! gearbox buffer size (increase if backpressure is present)
    g_GBX_BUF_SIZE        : positive := c_AURORA_ENC_WIDTH * 16;
    --! disable descrambler
    g_DISABLE_DESCRAMBLER : boolean  := false;
    --! use resource optimized gearbox
    g_USE_OPTIMIZED_GBX   : boolean  := true
  );
  port (
    --! input clock for encoded streams (e.g. 40 MHz in lpGBT)
    snk_clk_i     : in    std_logic;
    --! output clock
    src_clk_i     : in    std_logic;
    --! reset_i signal (on output clock)
    src_reset_i   : in    std_logic;
    -- AURORA ENCODED ELINK INTERFACE
    snk_valid_i   : in    std_logic_vector(g_N_LANES - 1 downto 0);                   --! valid aurora input
    snk_data_i    : in    slv_array_t(0 to g_N_LANES - 1)(g_LANE_WIDTH - 1 downto 0); --! aurora data
    --! @virtualbus Avalon-ST @dir out Aurora decoded source
    src_sop_o     : out   std_logic;                                                  --! start of packet
    src_eop_o     : out   std_logic;                                                  --! end of packet
    src_valid_o   : out   std_logic;                                                  --! valid packet
    src_error_o   : out   std_logic;                                                  --! discard packet
    src_data_o    : out   std_logic_vector(c_AURORA_DATA_WIDTH - 1 downto 0);         --! packet data output
    src_empty_o   : out   unsigned(log2ceil(c_AURORA_DATA_WIDTH / 8) - 1 downto 0);   --! packet empty
    src_link_up_o : out   std_logic                                                   --! link training done signal
  --! @end
  );
end entity aurora_rx;

architecture rtl of aurora_rx is

  constant c_GBX_BUF_WORDS   : positive := g_GBX_BUF_SIZE / g_LANE_WIDTH;
  signal   gearbox_data      : slv_array_t(0 to g_N_LANES - 1)(c_AURORA_ENC_WIDTH - 1 downto 0);
  signal   slip_data         : slv_array_t(0 to g_N_LANES - 1)(c_AURORA_ENC_WIDTH - 1 downto 0);
  signal   descrambled_data  : slv_array_t(0 to g_N_LANES - 1)(c_AURORA_ENC_WIDTH - 1 downto 0);
  signal   bond_data         : slv_array_t(0 to g_N_LANES - 1)(c_AURORA_ENC_WIDTH - 1 downto 0);
  signal   gearbox_valid     : std_logic_vector(g_N_LANES - 1 downto 0);
  signal   slip_valid        : std_logic_vector(g_N_LANES - 1 downto 0);
  signal   descrambled_valid : std_logic_vector(g_N_LANES - 1 downto 0);
  signal   bond_valid        : std_logic_vector(g_N_LANES - 1 downto 0);
  signal   sync_done         : std_logic_vector(g_N_LANES - 1 downto 0);
  signal   slip              : std_logic_vector(g_N_LANES - 1 downto 0);
  signal   bond_done         : std_logic;
  signal   snk_reset         : std_logic;

begin

  -- reset clock crossing
  u_synchro_reset : entity work.synchro_reset
    generic map (
      g_IN_POLARITY  => '1',
      g_OUT_POLARITY => '1',
      g_DURATION     => 1
    )
    port map (
      clk_i   => snk_clk_i,
      reset_i => src_reset_i,
      reset_o => snk_reset
    );

  src_link_up_o <= (andvec(sync_done and snk_valid_i)) and bond_done;

  gen_n_lanes : for i in 0 to g_N_LANES - 1 generate

    -- up sizing gearbox
    gen_opt_gbx : if g_USE_OPTIMIZED_GBX = true generate
    begin

      gbxup_opt_inst : entity colibri.cc_gearbox_up(rtl)
        generic map (
          g_INPUT_WIDTH  => g_LANE_WIDTH,
          g_OUTPUT_WIDTH => c_AURORA_ENC_WIDTH,
          g_BUFFER_WORDS => c_GBX_BUF_WORDS
        )
        port map (
          snk_clk_i   => snk_clk_i,
          src_clk_i   => src_clk_i,
          snk_reset_i => snk_reset,
          slip_i      => slip(i),
          snk_data_i  => snk_data_i(i),
          snk_valid_i => snk_valid_i(i),
          src_data_o  => slip_data(i),
          src_valid_o => slip_valid(i)
        );

    else generate

      gbxup_inst : entity colibri.cc_gearbox(rtl)
        generic map (
          g_INPUT_WIDTH  => g_LANE_WIDTH,
          g_OUTPUT_WIDTH => c_AURORA_ENC_WIDTH,
          g_BUFFER_WORDS => c_GBX_BUF_WORDS
        )
        port map (
          snk_clk_i   => snk_clk_i,
          src_clk_i   => src_clk_i,
          snk_reset_i => snk_reset,
          snk_data_i  => snk_data_i(i),
          snk_valid_i => snk_valid_i(i),
          snk_ready_o => open,
          src_data_o  => gearbox_data(i),
          src_valid_o => gearbox_valid(i),
          src_ready_i => '1'
        );

      -- slip buffer
      slip_buffer_inst : entity colibri.slip_buffer
        generic map (
          g_DATA_WIDTH => c_AURORA_ENC_WIDTH
        )
        port map (
          clk_i       => src_clk_i,
          reset_i     => src_reset_i,
          slip_i      => slip(i),
          snk_data_i  => gearbox_data(i),
          snk_valid_i => gearbox_valid(i),
          snk_ready_o => open,
          src_valid_o => slip_valid(i),
          src_ready_i => '1',
          src_data_o  => slip_data(i)
        );

    end generate gen_opt_gbx;

    -- descrambler
    gen_descrambler : if g_DISABLE_DESCRAMBLER  generate

      descrambled_valid <= slip_valid;
      descrambled_data  <= slip_data;

    else generate

      descrambler_inst : entity colibri.descrambler(rtl)
        generic map (

          g_DATA_WIDTH     => c_AURORA_DATA_WIDTH,
          g_SCRAMBLER_POLY => c_SCR_10GBASE
        )
        port map (
          clk_i       => src_clk_i,
          reset_i     => src_reset_i,
          snk_data_i  => slip_data(i)(c_AURORA_DATA_WIDTH - 1 downto 0),
          snk_valid_i => slip_valid(i),
          snk_ready_o => open,
          src_valid_o => descrambled_valid(i),
          src_ready_i => '1',
          src_data_o  => descrambled_data(i)(c_AURORA_DATA_WIDTH - 1 downto 0)
        );

      -- buffer to sync metadata and scrambled data
      meta_buffer_inst : entity work.meta_buffer(rtl)
        generic map (

          g_DATA_WIDTH => 2
        )
        port map (
          clk_i       => src_clk_i,
          reset_i     => src_reset_i,
          snk_data_i  => slip_data(i)(c_AURORA_ENC_WIDTH - 1 downto c_AURORA_DATA_WIDTH),
          snk_valid_i => slip_valid(i),
          snk_ready_o => open,
          src_valid_o => open,
          src_ready_i => '1',
          src_data_o  => descrambled_data(i)(c_AURORA_ENC_WIDTH - 1 downto c_AURORA_DATA_WIDTH)
        );

    end generate gen_descrambler;

    -- bitslip FSM
    bs_fsm_inst : entity work.block_sync_fsm(rtl)
      port map (
        clk_i       => src_clk_i,
        reset_i     => src_reset_i,
        snk_meta_i  => descrambled_data(i)(c_AURORA_ENC_WIDTH - 1 downto c_AURORA_ENC_WIDTH - 2),
        snk_valid_i => descrambled_valid(i),
        snk_slip_o  => slip(i),
        src_sync_o  => sync_done(i)
      );

  end generate gen_n_lanes;

  -- channel bonding generator
  gen_bond : if g_N_LANES > 1 generate

    ch_bond_inst : entity work.channel_bond(rtl)
      generic map (

        g_N_LANES      => g_N_LANES,
        g_BUF_SIZE     => 32,
        g_REGISTER_OUT => true
      )
      port map (
        clk_i       => src_clk_i,
        reset_i     => src_reset_i,
        snk_data_i  => descrambled_data,
        snk_valid_i => descrambled_valid,
        src_data_o  => bond_data,
        src_valid_o => bond_valid,
        src_bond_o  => bond_done
      );

  else
    generate
    bond_data  <= descrambled_data;
    bond_valid <= descrambled_valid;
    bond_done  <= '1';
  end generate gen_bond;

  -- decoder inst
  decoder_inst : entity work.aurora_st_decoder(rtl)
    generic map (

      g_N_LANES => g_N_LANES
    )
    port map (
      clk_i         => src_clk_i,
      reset_i       => src_reset_i,
      snk_data_i    => bond_data,
      snk_valid_i   => (and bond_valid),
      snk_link_up_i => src_link_up_o,
      snk_ready_o   => open,
      src_sop_o     => src_sop_o,
      src_eop_o     => src_eop_o,
      src_valid_o   => src_valid_o,
      src_error_o   => src_error_o,
      src_data_o    => src_data_o,
      src_empty_o   => src_empty_o
    );

end architecture rtl;
