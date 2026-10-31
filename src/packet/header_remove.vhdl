--! @title Generic Header Remover
--! @file header_remove.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 21-10-2024
--! @version 0.1

--! Release log:
--! - 0.1 first release

-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;

entity header_remove is
  generic (
    g_HEADER_BYTES : natural;
    g_DATA_WIDTH   : natural
  );
  port (
    clk_i        : in    std_logic;
    reset_i      : in    std_logic;
    --! @virtualbus Avalon-ST @dir in sink
    snk_sop_i    : in    std_logic;                                         --! start of packet
    snk_eop_i    : in    std_logic;                                         --! end of packet
    snk_valid_i  : in    std_logic;                                         --! packet valid
    snk_ready_o  : out   std_logic;                                         --! ready to receive
    snk_data_i   : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);       --! data input
    snk_empty_i  : in    unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0); --! empty input
    --! @end
    --! @virtualbus Avalon-ST @dir out source
    src_sop_o    : out   std_logic;                                         --! start of packet
    src_eop_o    : out   std_logic;                                         --! end of packet
    src_valid_o  : out   std_logic;                                         --! valid packet
    src_ready_i  : in    std_logic;                                         --! ready backpressure
    src_data_o   : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0);       --! packet data output
    src_empty_o  : out   unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0); --! packet empty
    --! retrieved header (sampled at start of packet)
    src_header_o : out   std_logic_vector(g_HEADER_BYTES * 8 - 1 downto 0)
  --! @end
  );
end entity header_remove;

architecture rtl of header_remove is

  -- mac header constants
  constant c_HEADER_WORDS : natural := div_ceil(g_HEADER_BYTES, (g_DATA_WIDTH / 8));
  constant c_HEADER_EMPTY : natural := c_HEADER_WORDS * (g_DATA_WIDTH / 8) - g_HEADER_BYTES;
  constant c_HEADER_VALID : natural := g_HEADER_BYTES - (c_HEADER_WORDS - 1) * (g_DATA_WIDTH / 8);

  -- types

  subtype header_array_t is slv_array_t(0 to c_HEADER_WORDS - 1)(g_DATA_WIDTH - 1 downto 0);

  type fsm_t is (S_IDLE, S_HEADER, S_DATA);

  subtype avst_t is avst_master_t(
    data(g_DATA_WIDTH - 1 downto 0),
    empty(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0)
  );

  type fsm_signals_t is record
    state    : fsm_t;
    avst     : avst_t;
    ready    : std_logic;
    head_cnt : integer;
    head_arr : header_array_t;
  end record fsm_signals_t;

  -- type related constants
  constant c_AVST_INIT : avst_t :=
  (
    valid => '0',
    sop   => '0',
    eop   => '0',
    empty => (others => '0'),
    data  => (others => '0')
  );

  constant c_FSM_INIT : fsm_signals_t :=
  (
    state    => S_IDLE,
    avst     => c_AVST_INIT,
    ready    => '0',
    head_cnt => 0,
    head_arr => (others => (others => '0'))
  );

  -- signals
  signal iavst            : avst_t := c_AVST_INIT;
  signal iavst_ready      : std_logic;
  signal shift_avst_ready : std_logic;

  signal rreg, rcmb : fsm_signals_t := c_FSM_INIT;

begin

  iavst.eop   <= snk_eop_i;
  iavst.valid <= snk_valid_i;
  iavst.data  <= snk_data_i;
  iavst.empty <= snk_empty_i;
  -- MAIN fsm
  proc_fsm_cmb : process (all) is

    variable v_int : fsm_signals_t;

  begin

    v_int       := rreg;
    v_int.ready := shift_avst_ready;

    -- data consumed
    if (rreg.avst.valid and shift_avst_ready) then
      v_int.avst := c_AVST_INIT;
    end if;

    -- backpressure
    v_int.ready := not rreg.avst.valid and shift_avst_ready;

    case rreg.state is

      when S_IDLE =>
        v_int       := c_FSM_INIT;
        v_int.state := S_HEADER;

      when S_HEADER =>

        if (iavst.valid and rreg.ready) then
          v_int.head_arr(rreg.head_cnt) := snk_data_i;
          if (rreg.head_cnt /= c_HEADER_WORDS - 1) then
            v_int.head_cnt := rreg.head_cnt + 1;
          else
            v_int.avst     := iavst;
            v_int.avst.sop := '1';
            v_int.state    := S_DATA;
          end if;
          if (iavst.eop = '1') then
            v_int.avst  := iavst;
            v_int.ready := '0';
            v_int.state := S_IDLE;
          end if;
        end if;

      when S_DATA =>

        if (iavst.valid and rreg.ready) then
          v_int.avst := iavst;
          if (iavst.eop = '1') then
            v_int.ready := '0';
            v_int.state := S_IDLE;
          end if;
        end if;

    end case;

    if (reset_i = '1') then
      v_int := c_FSM_INIT;
    end if;

    rcmb <= v_int;

  end process proc_fsm_cmb;

  rreg <= rcmb when rising_edge(clk_i);

  snk_ready_o <= rreg.ready;

  be_remove_lead_inst : entity colibri.be_remove_lead
    generic map (
      g_DATA_WIDTH   => g_DATA_WIDTH,
      g_REGISTER_OUT => true
    )
    port map (
      clk_i       => clk_i,
      reset_i     => reset_i,
      shl_i       => to_unsigned(c_HEADER_VALID,log2ceil(g_DATA_WIDTH / 8) + 1),
      snk_ready_o => shift_avst_ready,
      snk_valid_i => rreg.avst.valid,
      snk_sop_i   => rreg.avst.sop,
      snk_eop_i   => rreg.avst.eop,
      snk_empty_i => rreg.avst.empty,
      snk_data_i  => rreg.avst.data,
      src_ready_i => src_ready_i,
      src_valid_o => src_valid_o,
      src_sop_o   => src_sop_o,
      src_eop_o   => src_eop_o,
      src_empty_o => src_empty_o,
      src_data_o  => src_data_o,
      src_head_o  => open
    );

  proc_convert_header : process (all) is
  begin

    src_header_o <= (others => '0');

    if (src_valid_o and src_sop_o) then

      for i in 0 to c_HEADER_WORDS - 1 loop

        if (i < c_HEADER_WORDS - 1) then
          src_header_o(src_header_o'left - (i * g_DATA_WIDTH)
          downto src_header_o'length - ((i + 1) * g_DATA_WIDTH)) <= rreg.head_arr(i);
        else
          src_header_o((c_HEADER_VALID * 8) - 1 downto 0) <= rreg.head_arr(i)
            (rreg.head_arr'element'left downto c_HEADER_EMPTY * 8);
        end if;

      end loop;

    else
    end if;

  end process proc_convert_header;

end architecture rtl;
