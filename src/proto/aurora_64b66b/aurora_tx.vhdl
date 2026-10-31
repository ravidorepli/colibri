--! @brief Aurora 64b/66b Transmitter
--! @file aurora_tx.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 16-01-2024
--! @version 0.5

--! @copyright CERN 2026
--==================================================================================================

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
--! @brief Aurora 64b/66b Transmitter
--! @details
--! This entity implements a simplex, multi-lane Aurora 64b/66b Transmitter Chain (PMA/PCS).
--! Internal structure:
--!
--! ENCODER -> SCRAMBLER -> GEARBOX
--!
--! Release log:
--! - 0.1 first release
--! - 0.2 add sub-entity register control in generics
--! - 0.3 add multi-lane support
--! - 0.4 vhdl common library integration
--! - 0.4b Update to VHDL Style Guideline
--! - 0.5 use only two clocks (removed the need of lane_clk), add generic lane width

-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity aurora_tx is
  generic (

    --! Multi Lane Support
    g_N_LANES           : positive := 1;
    --! Lane width in bits
    g_LANE_WIDTH        : positive := 32;
    --! gearbox buffer size
    g_GBX_BUF_SIZE      : positive := 16 * c_AURORA_ENC_WIDTH;
    --! disable scrambler
    g_DISABLE_SCRAMBLER : boolean  := false
  );
  port (
    --! input clock
    snk_clk_i   : in    std_logic;
    --! input reset_i (on input clock)
    snk_reset_i : in    std_logic;
    --! output clock for encoded streams (e.g. 40 MHz in lpGBT)
    src_clk_i   : in    std_logic;
    --! @virtualbus Avalon-ST @dir in sink
    snk_sop_i   : in    std_logic;                                                --! start of packet
    snk_eop_i   : in    std_logic;                                                --! end of packet
    snk_valid_i : in    std_logic;                                                --! packet valid
    snk_ready_o : out   std_logic;                                                --! ready to receive
    snk_data_i  : in    std_logic_vector(c_AURORA_DATA_WIDTH - 1 downto 0);       --! data input
    snk_empty_i : in    unsigned(log2ceil(c_AURORA_DATA_WIDTH / 8) - 1 downto 0); --! empty input
    --! @end
    --! encoded output to elinks
    src_data_o  : out   slv_array_t(0 to g_N_LANES - 1)(g_LANE_WIDTH - 1 downto 0);
    src_valid_o : out   std_logic_vector(g_N_LANES - 1 downto 0);
    src_ready_i : in    std_logic_vector(g_N_LANES - 1 downto 0)
  );
end entity aurora_tx;

architecture rtl of aurora_tx is

  constant c_GBX_BUF_WORDS              : positive := g_GBX_BUF_SIZE / g_LANE_WIDTH;
  --! internal signals for data links
  signal encoded_data,  scrambled_data  : slv_array_t(0 to g_N_LANES - 1)(c_AURORA_ENC_WIDTH - 1 downto 0);
  --! internal signals for ready propagation
  signal gbx_ready,     scrambler_ready : std_logic_vector(g_N_LANES - 1 downto 0);
  --! internal signals for valid propagation
  signal encoded_valid, scrambled_valid : std_logic_vector(g_N_LANES - 1 downto 0);

begin

  encoder_inst : entity colibri.aurora_st_encoder(rtl)
    generic map (

      g_N_LANES => g_N_LANES
    )
    port map (
      clk_i       => snk_clk_i,
      reset_i     => snk_reset_i,
      snk_sop_i   => snk_sop_i,
      snk_eop_i   => snk_eop_i,
      snk_valid_i => snk_valid_i,
      snk_ready_o => snk_ready_o,
      snk_data_i  => snk_data_i,
      snk_empty_i => snk_empty_i,
      src_data_o  => encoded_data,
      src_ready_i => scrambler_ready,
      src_valid_o => encoded_valid
    );

  gen_n_lanes : for i in 0 to g_N_LANES - 1 generate
  begin

    gen_scrambler : if g_DISABLE_SCRAMBLER generate
      scrambled_valid(i) <= encoded_valid(i);
      scrambled_data(i)  <= encoded_data(i);
      scrambler_ready(i) <= gbx_ready(i);
    else generate
      -- scrambler
      scrambler_inst : entity colibri.scrambler(rtl)
        generic map (

          g_DATA_WIDTH     => c_AURORA_DATA_WIDTH,
          g_SCRAMBLER_POLY => c_SCR_10GBASE
        )
        port map (
          clk_i       => snk_clk_i,
          reset_i     => snk_reset_i,
          snk_data_i  => encoded_data(i)(c_AURORA_DATA_WIDTH - 1 downto 0),
          snk_valid_i => encoded_valid(i),
          snk_ready_o => scrambler_ready(i),
          src_data_o  => scrambled_data(i)(c_AURORA_DATA_WIDTH - 1 downto 0),
          src_ready_i => gbx_ready(i),
          src_valid_o => scrambled_valid(i)
        );

      -- buffer to sync metadata and scrambled data
      meta_buffer_inst : entity work.meta_buffer(rtl)
        generic map (

          g_DATA_WIDTH => 2
        )
        port map (
          clk_i       => snk_clk_i,
          reset_i     => snk_reset_i,
          snk_data_i  => encoded_data(i)(c_AURORA_ENC_WIDTH - 1 downto c_AURORA_DATA_WIDTH),
          snk_valid_i => encoded_valid(i),
          snk_ready_o => open,
          src_valid_o => open,
          src_ready_i => gbx_ready(i),
          src_data_o  => scrambled_data(i)(c_AURORA_ENC_WIDTH - 1 downto c_AURORA_DATA_WIDTH)
        );

    end generate gen_scrambler;

    -- gearbox
    gbxdown_inst : entity colibri.cc_gearbox(rtl)
      generic map (

        g_INPUT_WIDTH  => c_AURORA_ENC_WIDTH,
        g_OUTPUT_WIDTH => g_LANE_WIDTH,
        g_BUFFER_WORDS => c_GBX_BUF_WORDS
      )
      port map (
        snk_clk_i   => snk_clk_i,
        snk_reset_i => snk_reset_i,
        src_clk_i   => src_clk_i,
        snk_data_i  => scrambled_data(i),
        snk_valid_i => scrambled_valid(i),
        snk_ready_o => gbx_ready(i),
        src_data_o  => src_data_o(i),
        src_valid_o => src_valid_o(i),
        src_ready_i => src_ready_i(i)
      );

  end generate gen_n_lanes;

end architecture rtl;
