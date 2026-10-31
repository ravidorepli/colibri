--! @title Generic Header Adder
--! @file header_add.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 06-08-2024
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

entity header_add is
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
    --! standard logic vector header (sampled at start of packet)
    snk_header_i : in    std_logic_vector(g_HEADER_BYTES * 8 - 1 downto 0);
    --! @end
    --! @virtualbus Avalon-ST @dir out source
    src_sop_o    : out   std_logic;                                         --! start of packet
    src_eop_o    : out   std_logic;                                         --! end of packet
    src_valid_o  : out   std_logic;                                         --! valid packet
    src_ready_i  : in    std_logic;                                         --! ready backpressure
    src_data_o   : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0);       --! packet data output
    src_empty_o  : out   unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0)  --! packet empty
  --! @end
  );
end entity header_add;

architecture rtl of header_add is

  -- mac header constants
  constant c_HEADER_WORDS : integer := div_ceil(g_HEADER_BYTES, (g_DATA_WIDTH / 8));
  constant c_HEADER_EMPTY : integer := c_HEADER_WORDS * (g_DATA_WIDTH / 8) - g_HEADER_BYTES;
  constant c_HEADER_VALID : integer := g_HEADER_BYTES - (c_HEADER_WORDS - 1) * (g_DATA_WIDTH / 8);

  -- types

  subtype header_array_t is slv_array_t(0 to c_HEADER_WORDS - 1)(g_DATA_WIDTH - 1 downto 0);

  type fsm_t is (S_IDLE, S_ADD_HEADER, S_ADD_DATA, S_EOP);

  subtype avst_t is avst_master_t(
    data(g_DATA_WIDTH - 1 downto 0),
    empty(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0)
  );

  type fsm_signals_t is record
    state    : fsm_t;
    avst     : avst_t;
    head_cnt : integer;
    header   : std_logic_vector(g_HEADER_BYTES * 8 - 1 downto 0);
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
    head_cnt => 0,
    header   => (others => '0')
  );

  -- signals
  signal header_arr       : header_array_t;
  signal shift_avst       : avst_t;
  signal shift_avst_ready : std_logic;
  signal int_oavst        : avst_t;
  signal int_oavst_ready  : std_logic;

  signal fsm_reg, fsm_cmb : fsm_signals_t := c_FSM_INIT;

begin

  be_add_lead_inst : entity colibri.be_add_lead
    generic map (
      g_DATA_WIDTH => g_DATA_WIDTH
    )
    port map (
      clk_i       => clk_i,
      reset_i     => reset_i,
      shl_i       => to_unsigned(c_HEADER_VALID,log2ceil(g_DATA_WIDTH / 8) + 1),
      snk_ready_o => snk_ready_o,
      snk_valid_i => snk_valid_i,
      snk_sop_i   => snk_sop_i,
      snk_eop_i   => snk_eop_i,
      snk_empty_i => snk_empty_i,
      snk_data_i  => snk_data_i,
      snk_lead_i  => (others => '0'),
      src_ready_i => shift_avst_ready,
      src_valid_o => shift_avst.valid,
      src_sop_o   => shift_avst.sop,
      src_eop_o   => shift_avst.eop,
      src_empty_o => shift_avst.empty,
      src_data_o  => shift_avst.data
    );

  -- header conversions

  proc_convert_header : process (all) is
  begin

    for i in 0 to c_HEADER_WORDS - 1 loop

      if (i < c_HEADER_WORDS - 1) then
        header_arr(i) <= fsm_reg.header(fsm_reg.header'left - (i * g_DATA_WIDTH)
                                        downto fsm_reg.header'length - ((i + 1) * g_DATA_WIDTH));
      else
        header_arr(i) <= fsm_reg.header((c_HEADER_VALID * 8) - 1 downto 0)
          & (c_HEADER_EMPTY * 8 - 1 downto 0 => '0');
      end if;

    end loop;

  end process proc_convert_header;

  -- MAIN fsm
  proc_fsm_cmb : process (all) is

    variable v_int : fsm_signals_t;

  begin

    v_int            := fsm_reg;
    shift_avst_ready <= '0';

    -- register the header with the SOP signal
    if (snk_sop_i = '1' and snk_valid_i = '1' and snk_ready_o = '1') then
      v_int.header := snk_header_i;
    end if;

    case fsm_reg.state is

      when S_IDLE =>
        v_int.avst       := c_AVST_INIT;
        shift_avst_ready <= '0';

        if (shift_avst.valid = '1' and int_oavst_ready = '1') then
          v_int.avst.sop   := '1';
          v_int.avst.valid := '1';
          if (fsm_reg.head_cnt /= c_HEADER_WORDS - 1) then
            v_int.avst.data := header_arr(0);
            v_int.head_cnt  := fsm_reg.head_cnt + 1;
            v_int.state     := S_ADD_HEADER;
          else
            shift_avst_ready <= '1';
            v_int.avst       := shift_avst;
            v_int.avst.data  := header_arr(0) or shift_avst.data;
            v_int.head_cnt   := 0;
            v_int.state      := S_ADD_DATA;
            if (shift_avst.eop = '1') then
              v_int.state := S_EOP;
            end if;
          end if;
        end if;

      when S_ADD_HEADER =>

        if (int_oavst_ready = '1') then
          v_int.avst       := shift_avst;
          v_int.avst.sop   := '0';
          v_int.avst.valid := '1';
          if (fsm_reg.head_cnt /= c_HEADER_WORDS - 1) then
            v_int.avst.eop  := '0';
            v_int.avst.data := header_arr(fsm_reg.head_cnt);
            v_int.head_cnt  := fsm_reg.head_cnt + 1;
          else
            shift_avst_ready <= '1';
            v_int.avst.data  := header_arr(fsm_reg.head_cnt) or shift_avst.data;
            v_int.head_cnt   := 0;
            v_int.state      := S_ADD_DATA;
            if (shift_avst.eop = '1') then
              v_int.state := S_EOP;
            end if;
          end if;
        end if;

      when S_ADD_DATA =>

        if (int_oavst_ready = '1') then
          shift_avst_ready <= '1';
          v_int.avst       := shift_avst;
          v_int.avst.sop   := '0';
          if (shift_avst.eop = '1') then
            v_int.state := S_EOP;
          end if;
        end if;

      when S_EOP =>

        if (int_oavst_ready = '1') then
          v_int.avst  := c_AVST_INIT;
          v_int.state := S_IDLE;
        end if;

    end case;

    if (reset_i = '1') then
      v_int := c_FSM_INIT;
    end if;

    fsm_cmb <= v_int;

  end process proc_fsm_cmb;

  fsm_reg <= fsm_cmb when rising_edge(clk_i);

  -- type assignments

  int_oavst       <= fsm_reg.avst;
  int_oavst_ready <= src_ready_i;
  src_valid_o     <= int_oavst.valid;
  src_sop_o       <= int_oavst.sop;
  src_eop_o       <= int_oavst.eop;
  src_empty_o     <= int_oavst.empty;
  src_data_o      <= int_oavst.data;

end architecture rtl;
