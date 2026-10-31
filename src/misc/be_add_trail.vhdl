--! @title Big-Endian add trailing word module
--! @file be_add_trail.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 30-11-2023
--! @version 0.2

--! This module adds N_BYTES to the end of an incoming AvalonST packet. Adds trailing word `snk_trail_i` to the packet.
--! both `snk_trail_i` and `shl_i` are sampled at `snk_eop_i`.
--! Release log:
--! - 0.2 major rewrite to cover some corner cases
--! - 0.1 first release
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;

entity be_add_trail is
  generic (

    --! data bus width
    constant g_DATA_WIDTH : positive := 32
  );
  port (
    clk_i       : in    std_logic;                                     --! clock
    reset_i     : in    std_logic;                                     --! reset_i
    shl_i       : in    unsigned(log2ceil(g_DATA_WIDTH / 8) downto 0); --! trailing amount in bytes
    --! @virtualbus Avalon-ST @dir in sink
    snk_ready_o : out   std_logic;
    snk_valid_i : in    std_logic;
    snk_sop_i   : in    std_logic;
    snk_eop_i   : in    std_logic;
    snk_empty_i : in    unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);
    snk_data_i  : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    --! @end
    snk_trail_i : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    --! @virtualbus Avalon-ST @dir out source
    src_ready_i : in    std_logic;
    src_valid_o : out   std_logic;
    src_sop_o   : out   std_logic;
    src_eop_o   : out   std_logic;
    src_empty_o : out   unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);
    src_data_o  : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0)
  --! @end
  );
end entity be_add_trail;

architecture rtl of be_add_trail is

  constant c_DATA_BYTES : positive := g_DATA_WIDTH / 8;

  type fsm_t is (S_DATA, S_LATE_EOP);

  subtype avst_t is avst_master_t(
    data(g_DATA_WIDTH - 1 downto 0),
    empty(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0)
  );

  -- type related constants
  constant c_AVST_INIT : avst_t :=
  (
    valid => '0',
    sop   => '0',
    eop   => '0',
    empty => (others => '0'),
    data  => (others => '0')
  );

  type sig_t is record
    state : fsm_t;
    buf   : snk_data_i'subtype;
    shl   : natural range 0 to g_DATA_WIDTH / 8;
    ready : std_logic;
    avst  : avst_t;
  end record sig_t;

  constant c_FSM_INIT  : sig_t :=
  (
    state => S_DATA,
    buf   => (others => '0'),
    shl   => 0,
    ready => '0',
    avst  => c_AVST_INIT
  );
  signal   rreg        : sig_t := c_FSM_INIT;
  signal   rcmb        : sig_t;
  signal   skid        : avst_t;
  signal   skid_trail  : snk_trail_i'subtype;
  signal   skidb_trail : snk_trail_i'subtype;

begin

  -- avst buffer
  skid_buffer_inst : entity colibri.skid_buffer
    generic map (
      g_DATA_WIDTH => g_DATA_WIDTH
    )
    port map (
      clk_i       => clk_i,
      reset_i     => reset_i,
      snk_data_i  => snk_data_i,
      snk_empty_i => snk_empty_i,
      snk_keep_i  => (others => '0'),
      snk_sop_i   => snk_sop_i,
      snk_eop_i   => snk_eop_i,
      snk_valid_i => snk_valid_i,
      snk_ready_o => snk_ready_o,
      src_data_o  => skid.data,
      src_empty_o => skid.empty,
      src_keep_o  => open,
      src_sop_o   => skid.sop,
      src_eop_o   => skid.eop,
      src_valid_o => skid.valid,
      src_ready_i => rcmb.ready
    );

  -- lead skid buffer
  skid_trail <= snk_trail_i when snk_ready_o else
                skidb_trail;

  proc_skid_trail : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (snk_ready_o and snk_valid_i and not rcmb.ready) then
        skidb_trail <= snk_trail_i;
      end if;
    end if;

  end process proc_skid_trail;

  ------------------------------------------------------
  --                     MAIN FSM
  ------------------------------------------------------
  proc_fsm : process (all) is

    variable v_int : sig_t;

  begin

    v_int := rreg;

    -- data is consumed
    if (rreg.avst.valid = '1' and src_ready_i = '1') then
      v_int.avst := c_AVST_INIT;
    end if;

    v_int.ready := not v_int.avst.valid;

    case rreg.state is

      when S_DATA =>
        -- incoming packet and source is ready

        if (skid.valid = '1' and v_int.ready = '1') then
          v_int.avst.sop := skid.sop;
          if (skid.sop) then
            v_int.shl := to_integer(shl_i);
          end if;

          v_int.avst.eop   := skid.eop;
          v_int.avst.valid := skid.valid;
          v_int.avst.empty := skid.empty;

          for i in 0 to g_DATA_WIDTH / 8 - 1 loop
            if (i = to_integer(skid.empty)) then
              v_int.avst.data := skid.data(skid.data'left downto i * 8)
                & skid_trail(skid_trail'left downto g_DATA_WIDTH - i * 8);
              v_int.buf       := skid_trail(g_DATA_WIDTH - i * 8 - 1 downto 0) & (i * 8 - 1 downto 0 => '0');
            end if;
          end loop;

          if (skid.eop = '1') then
            -- need a second word for eop
            if (v_int.shl > to_integer(skid.empty)) then
              v_int.avst.empty := to_unsigned(g_DATA_WIDTH / 8 -
                                              (v_int.shl - to_integer(skid.empty)), skid.empty'length);

              v_int.avst.eop := '0';
              v_int.state    := S_LATE_EOP;
            else
              v_int.avst.empty := to_unsigned(to_integer(skid.empty) -
                                              v_int.shl, skid.empty'length);
            end if;
          end if;
        end if;

      when S_LATE_EOP =>

        if (v_int.ready) then
          v_int.avst.sop   := '0';
          v_int.avst.eop   := '1';
          v_int.avst.valid := '1';
          v_int.avst.empty := rreg.avst.empty;
          v_int.avst.data  := rreg.buf;
          v_int.state      := S_DATA;
        end if;

        v_int.ready := '0';

    end case;

    if (reset_i = '1') then
      v_int := c_FSM_INIT;
    end if;

    rcmb <= v_int;

  end process proc_fsm;

  rreg <= rcmb when rising_edge(clk_i);

  src_sop_o   <= rreg.avst.sop;
  src_eop_o   <= rreg.avst.eop;
  src_valid_o <= rreg.avst.valid;
  src_empty_o <= rreg.avst.empty;
  src_data_o  <= rreg.avst.data;

end architecture rtl;
