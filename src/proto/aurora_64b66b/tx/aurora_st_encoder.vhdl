--! @brief Aurora 64b/66b Ecnoder
--! @file aurora_st_encoder.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 27-06-2024
--! @version 0.4
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;

use work.aurora_const.all;

--==================================================================================================
--! @brief Aurora 64b/66b Ecnoder
--! @details
--! This entity implements a simplex, multi-lane Aurora 64b/66b Ecnoder.
--! A 64-bit wide Avalon Packeted Stream is encoded into multiple Aurora Encoded streams (lanes).
--! A channel bonding word is sent every 64 clock cycles when the encoder uses multiple lanes.
--! After reset, the entity will send idle words for 64 clock cycles to train the link.
--! Completed this phase, `snk_ready_o` is asserted.

--! changelog:
--! - 0.4 significant rewrite to clean up code (removed fifos)
--! - 0.3b Update to VHDL Style Guideline
--! - 0.3 Update to VHDL common library
--! - 0.2 Adding Channel Bonding Feature
--! - 0.1 first release
--
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity aurora_st_encoder is
  generic (
    --! Number of Lanes
    g_N_LANES    : positive := 1;
    --! internal fifo width
    g_FIFO_WORDS : positive := 8
  );
  port (
    --! clock
    clk_i       : in    std_logic;
    --! reset signal
    reset_i     : in    std_logic;
    --! @virtualbus Avalon-ST @dir in sink
    snk_sop_i   : in    std_logic;                                                --! start of packet
    snk_eop_i   : in    std_logic;                                                --! end of packet
    snk_valid_i : in    std_logic;                                                --! packet valid
    snk_ready_o : out   std_logic;                                                --! ready to receive
    snk_data_i  : in    std_logic_vector((c_AURORA_DATA_WIDTH) - 1 downto 0);     --! packet data
    snk_empty_i : in    unsigned(log2ceil(c_AURORA_DATA_WIDTH / 8) - 1 downto 0); --! packet empty bytes
    --! @end
    --! @virtualbus aurora_enc @dir out Aurora encoded source
    --! encoded data
    src_data_o  : out   slv_array_t(0 to g_N_LANES - 1)(c_AURORA_ENC_WIDTH - 1 downto 0);
    --! ready (backpressure)
    src_ready_i : in    std_logic_vector(g_N_LANES - 1 downto 0);
    --! data valid (always valid)
    src_valid_o : out   std_logic_vector(g_N_LANES - 1 downto 0)
  --! @end
  );
end entity aurora_st_encoder;

architecture rtl of aurora_st_encoder is

  --! fsm for packet encoding

  type fsm_t is (S_RESET, S_INIT, S_IDLE, S_DATA, S_EMPTY_SEP);

  -- shifters for control block insertion
  signal shift8_data           : std_logic_vector(c_AURORA_DATA_WIDTH - 9 downto 0);
  signal shift16_data          : std_logic_vector(c_AURORA_DATA_WIDTH - 17 downto 0);
  -- sync signal (initial data send)
  signal sync_done             : std_logic;
  signal sync_cnt              : unsigned(log2ceil(c_MAX_SYNC_CNT) downto 0);
  --  signal for channel bonding
  signal send_bond_frame       : std_logic := '0';
  --
  signal fifo_read             : std_logic;
  signal fifo_full, fifo_empty : std_logic;
  signal fifo_in,   fifo_out   : std_logic_vector(c_AURORA_ENC_WIDTH * g_N_LANES - 1 downto 0);

  type sig_t is record
    lanes     : slv_array_t(0 to g_N_LANES - 1)(c_AURORA_ENC_WIDTH - 1 downto 0);
    odata     : slv_array_t(0 to g_N_LANES - 1)(c_AURORA_ENC_WIDTH - 1 downto 0);
    ptr       : natural range 0 to g_N_LANES - 1;
    state     : fsm_t;
    reg_state : fsm_t;
    stall     : std_logic;
    empty     : std_logic;
    ready     : std_logic;
    valid     : std_logic;
  end record sig_t;

  constant c_FSM_INIT    : sig_t :=
  (
    lanes     => (others => (others => '0')),
    odata     => (others => c_IDLE_WORD),
    ptr       => 0,
    state     => S_RESET,
    reg_state => S_RESET,
    stall     => '0',
    empty     => '1',
    ready     => '0',
    valid     => '0'
  );
  signal   rreg,    rcmb : sig_t;

  function fill_lane (
    data  : snk_data_i'subtype;
    empty : snk_empty_i'subtype

  ) return std_logic_vector is

    variable v_lane        : std_logic_vector(c_AURORA_ENC_WIDTH - 1 downto 0);
    variable v_valid_block : std_logic_vector(7 downto 0);
    variable v_shift8      : std_logic_vector(c_AURORA_DATA_WIDTH - 9 downto 0);
    variable v_shift16     : std_logic_vector(c_AURORA_DATA_WIDTH - 17 downto 0);

  begin

    if (empty /= 1) then
      -- single sep block
      v_valid_block := std_logic_vector(resize(8 - empty, v_valid_block'length));
      v_shift16     := data(c_AURORA_DATA_WIDTH - 1 downto 16);
      v_lane        := c_CTRL_SH & c_SEP_BLOCK & v_valid_block & swap_endianness(v_shift16);
    elsif (empty = to_unsigned(1, empty'length)) then
      v_shift8 := data(c_AURORA_DATA_WIDTH - 1 downto 8);
      -- single sep 7 block
      v_lane := c_CTRL_SH & c_SEP7_BLOCK & swap_endianness(v_shift8);
    else
      v_lane := c_DATA_SH & data;
    end if;

    return v_lane;

  end function fill_lane;

begin

  --! initalization sync
  proc_sync_cnt : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        sync_cnt  <= (others => '0');
        sync_done <= '0';
      else
        if (sync_done = '0' and (and src_ready_i) = '1') then
          sync_cnt <= sync_cnt + 1;
          if (sync_cnt = to_unsigned(c_MAX_SYNC_CNT, sync_cnt'length)) then
            sync_done <= '1';
          end if;
        end if;
      end if;
    end if;

  end process proc_sync_cnt;

  --! channel bond sync
  gen_channel_bond : if g_N_LANES > 1 generate
    signal ch_bond_cnt : unsigned(7 downto 0) := (others => '0');
  begin

    proc_channel_bond_trigger : process (clk_i) is
    begin

      if rising_edge(clk_i) then
        if (reset_i = '1') then
          ch_bond_cnt     <= (others => '0');
          send_bond_frame <= '0';
        else
          if ((and src_ready_i) = '1') then
            send_bond_frame <= '0';
            ch_bond_cnt     <= ch_bond_cnt + 1;
            if (ch_bond_cnt = to_unsigned(c_CH_BOND_CYCLES, ch_bond_cnt'length)) then
              send_bond_frame <= '1';
              ch_bond_cnt     <= (others => '0');
            end if;
          end if;
        end if;
      end if;

    end process proc_channel_bond_trigger;

  end generate gen_channel_bond;

  rreg <= rcmb when rising_edge(clk_i);

  --! combinatorial part of the fsm
  proc_fsm_cmb : process (all) is

    variable v_int         : sig_t;
    variable v_valid_block : std_logic_vector(7 downto 0);

  begin

    v_int := rreg;

    -- buffer is empty
    if (rreg.empty = '1') then
      v_int.valid := '0';
    end if;

    -- if buffer is read and no bond frame is sent
    if ((and src_ready_i) = '1' and rreg.empty = '0' and send_bond_frame = '0') then
      v_int.valid := '0';
      v_int.empty := '1';
    end if;

    v_int.ready := v_int.empty;

    if (v_int.empty = '1') then
      v_int.lanes(rreg.ptr) := c_IDLE_WORD;
    end if;

    case rreg.state is

      when S_RESET =>
        v_int.ready := '0';
        v_int.state := S_INIT;

      when S_INIT =>
        v_int.ready := '0';

        if (sync_done = '1') then
          v_int.state := S_IDLE;
        end if;

      when S_IDLE =>

        -- incoming packets and buffer available
        if (snk_valid_i = '1' and v_int.empty = '1' and snk_sop_i = '1') then
          -- single word behaviour (EOP)
          if (snk_eop_i = '1') then
            if (snk_empty_i /= 0) then
              v_int.lanes(rreg.ptr) := fill_lane(snk_data_i, snk_empty_i);
              v_int.state           := S_IDLE;
            else
              v_int.lanes(rreg.ptr) := c_DATA_SH & swap_endianness(snk_data_i);
              v_int.state           := S_EMPTY_SEP;
            end if;
          else
            -- multi word behaviour (NO EOP)
            v_int.lanes(rreg.ptr) := c_DATA_SH & swap_endianness(snk_data_i);
            v_int.state           := S_DATA;
          end if;
        end if;

      when S_DATA =>
        -- incoming packets and buffer available
        if (snk_valid_i = '1' and v_int.empty = '1') then
          -- single word behaviour (EOP)
          if (snk_eop_i = '1') then
            if (snk_empty_i /= 0) then
              v_int.lanes(rreg.ptr) := fill_lane(snk_data_i, snk_empty_i);
              v_int.state           := S_IDLE;
            else
              v_int.lanes(rreg.ptr) := c_DATA_SH & swap_endianness(snk_data_i);
              v_int.state           := S_EMPTY_SEP;
            end if;
          else
            -- multi word behaviour (NO EOP)
            v_int.lanes(rreg.ptr) := c_DATA_SH & swap_endianness(snk_data_i);
          end if;
        end if;

      -- send empty separator when data is multiple of 64 bits
      when S_EMPTY_SEP =>
        -- back propagate not ready
        v_int.ready := '0';

        if (v_int.empty = '1') then
          v_int.lanes(rreg.ptr) := c_CTRL_SH & c_SEP_BLOCK & (shift8_data'range => '0');
          v_int.state           := S_IDLE;
        end if;

    end case;

    if (v_int.empty = '1') then
      if (v_int.ptr = g_N_LANES - 1) then
        v_int.ptr   := 0;
        v_int.empty := '0';
        v_int.valid := '1';
      else
        v_int.ptr := rreg.ptr + 1;
      end if;
    end if;

    -- output is consumed
    if (and src_ready_i = '1') then
      if (send_bond_frame) then
        v_int.odata := (others => c_CB_WORD);
      elsif (rreg.valid) then
        v_int.odata := rreg.lanes;
      else
        v_int.odata := (others => c_IDLE_WORD);
      end if;
    end if;

    -- drive output lanes

    if (reset_i) then
      v_int := c_FSM_INIT;
    end if;

    rcmb <= v_int;

  end process proc_fsm_cmb;

  snk_ready_o <= rcmb.ready;
  src_data_o  <= rreg.odata;

  src_valid_o <= (others => not reset_i);

end architecture rtl;
