--! @file aurora_st_decoder.vhdl
--! @brief Aurora 64b/66b Decoder
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
  use colibri.types.all;

use work.aurora_const.all;
--==================================================================================================
--! @brief Aurora 64b/66b Decoder
--! @details
--! This entity implements a simplex, multi-lane Aurora 64b/66b decoder.
--! It expects a 66-bit wide Aurora Encoded stream in input.
--! The `snk_link_up_i` input signals that the previous components have finished LT/CB.
--! Once the link is up, the decoder waits for a separator or separator-7 packet delimiter.
--! The first packet is dropped since there's no knowledge of its start or length.
--! Packets are then output in a Avalon Stream interface style.
--! The `snk_error_o` output is driven when:
--!   - link drops in the middle of a packet (truncation)
--!   - a channel bond word is received when configured for single lane (lane mismatch)
--!
--! Changelog:
--! - 0.5 Channel Bond lane mismatch error handling
--! - 0.4 code cleanup rewriting
--! - 0.3b update to vhdl style guideline
--! - 0.3 Add Multi-Lane support
--! - 0.2 FIX behaviour when valid is oscillating
--! - 0.1 first release

-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity aurora_st_decoder is
  generic (
    --! Number of Lanes
    g_N_LANES    : positive := 1;
    --! internal fifo width
    g_FIFO_WORDS : positive := 8
  );
  port (
    --! clock
    clk_i         : in    std_logic;
    --! reset signal
    reset_i       : in    std_logic;
    snk_link_up_i : in    std_logic; --! link training and channel bonding done signal

    -- AURORA ENCODED INTERFACE
    --! @virtualbus aurora_enc @dir in Aurora encoded sink
    snk_data_i  : in    slv_array_t(0 to g_N_LANES - 1)(c_AURORA_ENC_WIDTH - 1 downto 0);
    snk_valid_i : in    std_logic;                                               --! encoded data valid
    snk_ready_o : out   std_logic;                                               --! backpressure signal
    --! @end
    --! @virtualbus Avalon-ST @dir out Aurora decoded source
    src_sop_o   : out   std_logic;                                               --! start of packet
    src_eop_o   : out   std_logic;                                               --! end of packet
    src_valid_o : out   std_logic;                                               --! packet valid signal
    src_error_o : out   std_logic;                                               --! discard packet packet
    src_data_o  : out   std_logic_vector(c_AURORA_DATA_WIDTH - 1 downto 0);      --! packet data
    src_empty_o : out   unsigned(log2ceil(c_AURORA_DATA_WIDTH / 8) - 1 downto 0) --! packet empty
  --! @end
  );
end entity aurora_st_decoder;

architecture rtl of aurora_st_decoder is

  --! fsm for packet encoding

  type fsm_t is (S_RESET, S_IDLE, S_WAIT_SEP, S_DATA, S_WAIT_EOP);

  signal snk_reset : std_logic;

  impure function empty_from_valid (v_valid_blocks : std_logic_vector) return unsigned is

    variable v_empty_num : natural range 0 to c_AURORA_DATA_WIDTH / 8;

  begin

    v_empty_num := c_AURORA_DATA_WIDTH / 8 - to_integer(unsigned(v_valid_blocks));
    return to_unsigned(v_empty_num, src_empty_o'length);

  end function empty_from_valid;

  type sig_t is record
    state     : fsm_t;
    lanes_ptr : natural range 0 to g_N_LANES - 1;
    idata     : std_logic_vector(c_AURORA_ENC_WIDTH - 1 downto 0);
    ivalid    : std_logic;
    iready    : std_logic;
    odata     : std_logic_vector(c_AURORA_DATA_WIDTH - 1 downto 0);
    valid     : std_logic;
    lookahead : std_logic;
    sop       : std_logic;
    eop       : std_logic;
    error     : std_logic;
    empty     : src_empty_o'subtype;
  end record sig_t;

  constant c_FSM_INIT : sig_t :=
  (
    lanes_ptr => 0,
    idata     => (others => '0'),
    ivalid    => '0',
    iready    => '0',
    odata     => (others => '0'),
    state     => S_RESET,
    valid     => '0',
    lookahead => '0',
    sop       => '0',
    eop       => '0',
    error     => '0',
    empty     => (others => '0')

  );
  signal rreg, rcmb : sig_t;

  -- fifo signals
  signal ififo_data  : snk_data_i'subtype;
  signal ififo_slv   : std_logic_vector(c_AURORA_ENC_WIDTH * g_N_LANES - 1 downto 0);
  signal ofifo_data  : snk_data_i'subtype;
  signal ofifo_slv   : std_logic_vector(c_AURORA_ENC_WIDTH * g_N_LANES - 1 downto 0);
  signal ofifo_valid : snk_valid_i'subtype;
  signal fifo_empty  : std_logic;
  signal fifo_full   : std_logic;

  -- filter signal
  signal filter_valid  : snk_valid_i'subtype;
  -- flag for channel bonding
  signal ch_bond_lane0 : std_logic;

  procedure parse_ctrl (
    reg : in sig_t;
    var : inout sig_t
  ) is
  begin

    if (rreg.state = S_DATA) then
      var.sop := '1';
    else
      var.sop := '0';
    end if;

    case rreg.idata(ctrl_block_range) is

      when c_SEP7_BLOCK =>
        var.valid := '1';
        var.eop   := '1';
        var.odata := swap_endianness(rreg.idata(c_AURORA_DATA_WIDTH - 9 downto 0)) & 8x"00";
        var.empty := to_unsigned(1, src_empty_o'length);
        var.state := S_DATA;

      when c_SEP_BLOCK =>
        -- if is not an empty SEPARATOR
        if (rreg.idata(valid_block_range) /= (valid_block_range => '0')) then
          var.valid := '1';
          var.eop   := '1';
          var.odata := swap_endianness(rreg.idata(c_AURORA_DATA_WIDTH - 17 downto 0)) & 16x"00";
          var.empty := empty_from_valid(rreg.idata(valid_block_range));
          var.state := S_DATA;
        end if;

      when others =>
        var.sop   := '0';
        var.valid := '0';

    end case;

  end procedure parse_ctrl;

begin

  -- FILTER OUT CHANNEL BONDING AND IDLE BLOCKS
  proc_filter : process (all) is

    variable v_valid : std_logic_vector(g_N_LANES - 1 downto 0);

  begin

    v_valid      := (others => '0');
    filter_valid <= '0';

    if (snk_valid_i = '1') then

      for i in 0 to g_N_LANES - 1 loop
        if (snk_data_i(i)(header_range) = c_CTRL_SH and
            (snk_data_i(i)(ctrl_block_range) = c_IDLE_CB_BLOCK)) then
          v_valid(i) := '1';
        end if;
      end loop;

      -- all lanes are not idle or ch bond
      if (and(v_valid) = '0') then
        filter_valid <= '1';
      end if;
    end if;

  end process proc_filter;

  -- check if word matches bond frame
  ch_bond_lane0 <= '1' when snk_data_i(0)(c_AURORA_ENC_WIDTH - 1 downto c_AURORA_ENC_WIDTH - 18) = c_CTRL_SH &
                            c_IDLE_CB_BLOCK & c_CB_CODE and snk_valid_i = '1' else
                   '0';
  ififo_data    <= snk_data_i;
  ififo_slv     <= slv_array_to_slv(ififo_data, c_AURORA_ENC_WIDTH);
  ofifo_data    <= slv_to_slv_array(ofifo_slv, c_AURORA_ENC_WIDTH);
  -- fifo to manage decoding backpressure
  fifo_inst : entity work.fifo
    generic map (
      g_NUM_WORDS    => g_FIFO_WORDS,
      g_INPUT_WIDTH  => ififo_slv'length,
      g_OUTPUT_WIDTH => ififo_slv'length,
      g_ENABLE_FWFT  => true
    )
    port map (
      clk_i   => clk_i,
      reset_i => reset_i,
      data_i  => ififo_slv,
      wrreq_i => filter_valid,
      rdreq_i => rcmb.iready,
      q_o     => ofifo_slv,
      usedw_o => open,
      empty_o => fifo_empty,
      full_o  => fifo_full
    );

  ofifo_valid <= not fifo_empty;
  snk_ready_o <= not fifo_full;

  ----------------------------------------
  --           DECODING FSM             --
  ----------------------------------------
  rreg <= rcmb when rising_edge(clk_i);
  --! combinatorial part of the FSM
  proc_fsm_cmb : process (all) is

    variable v_int         : sig_t;
    variable v_valid_block : std_logic_vector(7 downto 0);

  begin

    v_int        := rreg;
    v_int.idata  := ofifo_data(rreg.lanes_ptr);
    v_int.ivalid := ofifo_valid;
    v_int.iready := '0';

    if (rreg.valid = '1') then
      v_int.valid := '0';
      v_int.sop   := '0';
      v_int.eop   := '0';
      v_int.error := rreg.error and not rreg.eop;
      v_int.empty := (others => '0');
      v_int.odata := (others => '0');
    end if;

    if (ofifo_valid) then
      if (rreg.lanes_ptr = g_N_LANES - 1) then
        v_int.lanes_ptr := 0;
        v_int.iready    := '1';
      else
        v_int.lanes_ptr := rreg.lanes_ptr + 1;
      end if;
    else
      v_int.iready := '1';
    end if;

    case rreg.state is

      when S_RESET =>
        v_int.state := S_IDLE;

      when S_IDLE =>
        v_int.valid := '0';
        v_int.sop   := '0';
        v_int.eop   := '0';
        -- if aurora link is up and running
        if (snk_link_up_i = '1') then
          v_int.state := S_WAIT_SEP;
        end if;

      when S_WAIT_SEP =>
        v_int.valid := '0';
        v_int.sop   := '0';
        v_int.eop   := '0';
        -- look for a separator
        if (rreg.ivalid = '1' and
            rreg.idata(header_range) = c_CTRL_SH and
            (rreg.idata(ctrl_block_range) = c_SEP7_BLOCK or
              rreg.idata(ctrl_block_range) = c_SEP_BLOCK)) then
          v_int.state := S_DATA;
        end if;

        -- if link drops
        if (snk_link_up_i = '0') then
          v_int.state := S_WAIT_SEP;
        end if;

      when S_DATA =>
        v_int.eop := '0';
        -- if the buffer word is a DATA word wait for a new word in input (LOOKAHEAD)
        if (rreg.ivalid = '1') then
          v_int.valid := '0';
          if (rreg.idata(header_range) = c_DATA_SH) then
            v_int.odata     := swap_endianness(rreg.idata(c_AURORA_DATA_WIDTH - 1 downto 0));
            v_int.sop       := '1';
            v_int.lookahead := '1';

          -- if buffered word is CONTROL
          elsif (rreg.idata(header_range) = c_CTRL_SH) then
            parse_ctrl(rreg, v_int);
          end if;
        end if;

        if (v_int.lookahead = '1' and v_int.ivalid = '1') then
          v_int.valid     := '1';
          v_int.lookahead := '0';
          -- if new word is a empty SEPARATOR, issue EOP
          if (v_int.idata(header_range) = c_CTRL_SH and
              v_int.idata(ctrl_block_range) = c_SEP_BLOCK and
              v_int.idata(valid_block_range) = (valid_block_range => '0')) then
            v_int.eop := '1';
          else
            v_int.state := S_WAIT_EOP;
          end if;
        end if;

      when S_WAIT_EOP =>
        v_int.sop := '0';
        -- if the buffer word is a DATA word wait for a new word in input (LOOKAHEAD)
        if (rreg.ivalid = '1') then
          v_int.valid := '0';
          if (rreg.idata(header_range) = c_DATA_SH) then
            v_int.odata     := swap_endianness(rreg.idata(c_AURORA_DATA_WIDTH - 1 downto 0));
            v_int.lookahead := '1';
          -- if buffered word is CONTROL
          elsif (rreg.idata(header_range) = c_CTRL_SH) then
            parse_ctrl(rreg, v_int);
          end if;
        end if;

        if (v_int.lookahead = '1' and v_int.ivalid = '1') then
          v_int.valid     := '1';
          v_int.lookahead := '0';
          -- if new word is a empty SEPARATOR, issue EOP
          if (v_int.idata(header_range) = c_CTRL_SH and
              v_int.idata(ctrl_block_range) = c_SEP_BLOCK and
              v_int.idata(valid_block_range) = (valid_block_range => '0')) then
            v_int.eop   := '1';
            v_int.state := S_DATA;
          end if;
        end if;

    end case;

    -- if link drops
    if (snk_link_up_i = '0' and
        (rreg.state = S_DATA or rreg.state = S_WAIT_EOP)) then
      v_int.eop   := '1';
      v_int.valid := '1';
      v_int.error := '1';
      v_int.state := S_WAIT_SEP;
    end if;

    -- if channel bonding is present with one single lane
    if (snk_link_up_i = '1' and g_N_LANES = 1 and ch_bond_lane0 = '1') then
      v_int.error := '1';
    end if;

    if (reset_i = '1') then
      v_int := c_FSM_INIT;
    end if;

    rcmb <= v_int;

  end process proc_fsm_cmb;

  src_data_o  <= rreg.odata;
  src_valid_o <= rreg.valid;
  src_sop_o   <= rreg.sop;
  src_eop_o   <= rreg.eop;
  src_error_o <= rreg.error;
  src_empty_o <= rreg.empty;

end architecture rtl;
