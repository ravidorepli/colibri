--! @brief Aurora Multi Lane Bonding
--! @file channel_bond.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 16-01-2024
--! @version 0.1b
--! @copyright CERN 2026
--==================================================================================================

-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;

use work.aurora_const.all;

--==================================================================================================
--! @brief Aurora Multi Lane Bonding
--! @details
--! This entity implements multi lane channel bonding (CB).
--! Each lane is fed to a dedicated buffer (FIFO).
--! The FIFOs are read continuously until a CB word is seen.
--! Once all FIFOs have a CB word on their output, the channel skews are compensated.
--! The link is now bonded and the `src_bond_o` is asserted.

--! changelog:
--! - 0.1 first release
--! - 0.1b: update to lhcb vhdl style guideline

-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity channel_bond is
  generic (

    g_N_LANES      : positive := 1;
    g_BUF_SIZE     : positive := 8;
    g_REGISTER_OUT : boolean  := true
  );
  port (
    clk_i       : in    std_logic;
    reset_i     : in    std_logic;
    -- aurora multiple channel input
    snk_data_i  : in    slv_array_t(0 to g_N_LANES - 1)(c_AURORA_ENC_WIDTH - 1 downto 0);
    snk_valid_i : in    std_logic_vector(g_N_LANES - 1 downto 0);
    -- channel syncronized output
    src_data_o  : out   slv_array_t(0 to g_N_LANES - 1)(c_AURORA_ENC_WIDTH - 1 downto 0);
    src_valid_o : out   std_logic_vector(g_N_LANES - 1 downto 0);
    src_bond_o  : out   std_logic
  );
end entity channel_bond;

architecture rtl of channel_bond is

  signal read_en       : std_logic_vector(g_N_LANES - 1 downto 0);
  signal fifo_empty    : std_logic_vector(g_N_LANES - 1 downto 0);
  signal fifo_full     : std_logic_vector(g_N_LANES - 1 downto 0);
  signal is_bond_frame : std_logic_vector(g_N_LANES - 1 downto 0);
  signal o_data        : slv_array_t(0 to g_N_LANES - 1)(c_AURORA_ENC_WIDTH - 1 downto 0);
  signal o_valid       : std_logic_vector(g_N_LANES - 1 downto 0);
  signal reset_i_fifo  : std_logic_vector(g_N_LANES - 1 downto 0);
  signal bond_done     : std_logic_vector(g_N_LANES - 1 downto 0);

begin

  src_data_o  <= o_data when registered(clk_i, g_REGISTER_OUT);
  src_valid_o <= o_valid when registered(clk_i, g_REGISTER_OUT);
  src_bond_o  <= and bond_done when registered(clk_i, g_REGISTER_OUT);

  gen_fifos : for i in 0 to g_N_LANES - 1 generate

    ch_bond_fifo : entity colibri.fifo(rtl)
      generic map (

        g_NUM_WORDS    => g_BUF_SIZE,
        g_INPUT_WIDTH  => c_AURORA_ENC_WIDTH,
        g_OUTPUT_WIDTH => c_AURORA_ENC_WIDTH
      )
      port map (
        reset_i => and reset_i_fifo,
        clk_i   => clk_i,
        data_i  => snk_data_i(i),
        wrreq_i => snk_valid_i(i),
        rdreq_i => read_en(i),
        q_o     => o_data(i),
        empty_o => fifo_empty(i),
        full_o  => fifo_full(i)
      );

  end generate gen_fifos;

  gen_lane_fsm : for i in 0 to g_N_LANES - 1 generate

    type fsm_t is (S_RESET_I, S_IDLE, S_TEST_BOND, S_ALIGN, S_CH_BOND);

    signal state      : fsm_t := s_idle;
    signal next_state : fsm_t;
  begin
    -- check if word matches bond frame
    is_bond_frame(i) <= '1' when o_data(i)(c_AURORA_ENC_WIDTH - 1 downto c_AURORA_ENC_WIDTH - 18) = c_CTRL_SH &
                                 c_IDLE_CB_BLOCK & c_CB_CODE else
                        '0';

    proc_fsm_clk : process (clk_i) is
    begin

      if rising_edge(clk_i) then
        if (reset_i = '1') then
          state        <= s_reset_i;
          o_valid(i)   <= '0';
          bond_done(i) <= '0';
        else
          bond_done(i) <= '0';
          o_valid(i)   <= '0';
          state        <= next_state;
          if (state = s_ch_bond) then
            bond_done(i) <= '1';
            o_valid(i)   <= read_en(i);
          end if;
        end if;
      end if;

    end process proc_fsm_clk;

    proc_fsm_cmb : process (all) is
    begin

      reset_i_fifo(i) <= '0';
      next_state      <= state;
      read_en(i)      <= '0';

      case state is

        when s_reset_i =>
          next_state      <= s_idle;
          reset_i_fifo(i) <= '1';

        when s_idle =>

          if (or fifo_empty = '0') then
            next_state <= s_test_bond;
            read_en(i) <= '1'; -- start reading fifo
          end if;

        when s_test_bond =>
          read_en(i) <= '1';

          if (is_bond_frame(i)) then
            read_en(i) <= '0'; -- stop reading
            if (and is_bond_frame) then
              next_state <= s_ch_bond;
            else
              next_state <= s_align;
            end if;
          end if;

        when s_align =>

          if (and is_bond_frame) then -- all synched
            next_state <= s_ch_bond;
          end if;

        when s_ch_bond =>

          if (not (or fifo_empty)) then
            read_en(i) <= '1'; -- start reading
          end if;

          if ((and o_valid) and (or is_bond_frame) and (not (and is_bond_frame))) then
            reset_i_fifo(i) <= '1';
            next_state      <= s_idle;
          end if;

      end case;

      if (or fifo_full) then
        reset_i_fifo(i) <= '1';
        next_state      <= s_idle;
      end if;

    end process proc_fsm_cmb;

  end generate gen_lane_fsm;

end architecture rtl;
