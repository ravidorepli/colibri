--! @brief Block Sync FSM
--! @file block_sync_fsm.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 16-01-2024
--! @version 0.1b
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;

use work.aurora_const.all;
--==================================================================================================
--! @brief Block Sync FSM
--! @details
--! This entity implements the Finite State Machine that determines and check the link lock status.
--! See Aurora FSM flowchart and IEEE 802.3ae fig 49-14 (rev.2022)

--! changelog:
--! - 0.1 first release
--! - 0.1b: update to lhcb vhdl style guideline
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity block_sync_fsm is
  generic (
    --! sync headers used to determine lock
    g_SH_CNT_MAX         : positive := 64;
    --! sync headers used to determine lock failure
    g_SH_INVALID_CNT_MAX : positive := 16;
    --! cycles to wait before reset_i after a slip
    g_SLIP_CNT_MAX       : positive := 32
  );
  port (
    --! global clock signal
    clk_i       : in    std_logic;
    --! synchronous reset_i
    reset_i     : in    std_logic;
    --! sync header input
    snk_meta_i  : in    std_logic_vector(1 downto 0);
    --! valid input
    snk_valid_i : in    std_logic;
    --! drive gearbox slip
    snk_slip_o  : out   std_logic;
    --! return lock status
    src_sync_o  : out   std_logic
  );
end entity block_sync_fsm;

architecture rtl of block_sync_fsm is

  --! fsm states

  type fsm_t is (S_LOCK_INIT, S_RESET_CNT, S_TEST_SH, S_VALID_SH, S_INVALID_SH, S_64_GOOD, S_SLIP);

  signal state      : fsm_t := S_LOCK_INIT;
  signal next_state : fsm_t;

  signal sh_found       : boolean;
  signal block_lock     : std_logic;
  signal slip_done      : boolean;
  signal sh_cnt         : unsigned(log2ceil(g_SH_CNT_MAX) downto 0);
  signal sh_invalid_cnt : unsigned(log2ceil(g_SH_INVALID_CNT_MAX) downto 0);
  signal slip_cnt       : unsigned(log2ceil(g_SLIP_CNT_MAX) downto 0);

begin

  -- valid sync header
  sh_found <= (snk_meta_i = c_CTRL_SH) or (snk_meta_i = c_DATA_SH);

  --! sychronous fsm process
  --! state transitions and counters
  proc_fsm_clk : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        state          <= S_LOCK_INIT;
        sh_cnt         <= (others => '0');
        sh_invalid_cnt <= (others => '0');
        slip_cnt       <= (others => '0');
        slip_done      <= false;
      else
        state <= next_state;

        case state is

          when S_RESET_CNT =>
            sh_cnt         <= (others => '0');
            sh_invalid_cnt <= (others => '0');
            slip_cnt       <= (others => '0');
            slip_done      <= false;

          when S_VALID_SH =>
            sh_cnt   <= sh_cnt + 1;
            slip_cnt <= (others => '0');

          when S_INVALID_SH =>
            sh_cnt         <= sh_cnt + 1;
            sh_invalid_cnt <= sh_invalid_cnt + 1;
            slip_cnt       <= (others => '0');

          when S_SLIP =>
            slip_cnt  <= slip_cnt + 1;
            slip_done <= slip_cnt = g_SLIP_CNT_MAX;

          when others =>
            null;

        end case;

        src_sync_o <= block_lock;
      end if;
    end if;

  end process proc_fsm_clk;

  --! fsm combinatorial process
  proc_fsm_comb : process (all) is
  begin

    next_state <= state;
    block_lock <= src_sync_o;
    snk_slip_o <= '0';

    case state is

      -- initialization state
      when S_LOCK_INIT =>
        block_lock <= '0';
        next_state <= S_RESET_CNT;

      -- reset_i counters state
      when S_RESET_CNT =>
        next_state <= S_TEST_SH;

      -- test for sync header
      when S_TEST_SH =>

        if (snk_valid_i = '1') then
          if (sh_found) then
            next_state <= S_VALID_SH;
          else
            next_state <= S_INVALID_SH;
          end if;
        end if;

      -- valid header
      when S_VALID_SH =>

        if (sh_cnt = g_SH_CNT_MAX) then
          if (sh_invalid_cnt = 0) then
            next_state <= S_64_GOOD;
          elsif (sh_invalid_cnt > 0) then
            next_state <= S_RESET_CNT;
          end if;
        else
          next_state <= S_TEST_SH;
        end if;

      -- invalid header
      when S_INVALID_SH =>

        if (block_lock = '0' or sh_invalid_cnt = g_SH_INVALID_CNT_MAX) then
          next_state <= S_SLIP;
          snk_slip_o <= '1';
        else -- block_lock = '1' and sh_invalid_cnt < g_SH_INVALID_CNT_MAX
          if (sh_cnt = g_SH_CNT_MAX) then
            next_state <= S_RESET_CNT;
          else
            next_state <= S_TEST_SH;
          end if;
        end if;

      -- lock completed
      when S_64_GOOD =>
        block_lock <= '1';
        next_state <= S_RESET_CNT;

      -- gearbox slip
      when S_SLIP =>

        if (slip_done) then
          next_state <= S_RESET_CNT;
        end if;

        block_lock <= '0';

    end case;

  end process proc_fsm_comb;

end architecture rtl;
