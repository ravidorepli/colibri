--! @title Big-Endian Packet remove leading bytes module
--! @file be_remove_lead.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 06-12-2023
--! @version 0.1

--! This module shifts an incoming AvalonST packet by a defined amount to the left.
--! Removes N bytes (shl_i) and returns the removed bytes in src_head_o.
--! This module has been designed to cut headers from packets.
--! `src_head_o` is output when `src_sop_o` is issued.
--! Release log:
--! - 0.2 major rewrite to fix some issues
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

entity be_remove_lead is
  generic (

    --! data bus width
    g_DATA_WIDTH   : positive := 32;
    --! add registers to the output
    g_REGISTER_OUT : boolean  := false
  );
  port (
    clk_i       : in    std_logic;                                     --! clock
    reset_i     : in    std_logic;                                     --! reset_i
    shl_i       : in    unsigned(log2ceil(g_DATA_WIDTH / 8) downto 0); --! shift amount in bytes
    --! @virtualbus Avalon-ST @dir in sink
    snk_ready_o : out   std_logic;
    snk_valid_i : in    std_logic;
    snk_sop_i   : in    std_logic;
    snk_eop_i   : in    std_logic;
    snk_empty_i : in    unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);
    snk_data_i  : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    --! @end
    --! @virtualbus Avalon-ST @dir out source
    src_ready_i : in    std_logic;
    src_valid_o : out   std_logic;
    src_sop_o   : out   std_logic;
    src_eop_o   : out   std_logic;
    src_empty_o : out   unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);
    src_data_o  : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    --! @end
    src_head_o  : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0)
  );
end entity be_remove_lead;

architecture rtl of be_remove_lead is

  constant c_DATA_BYTES : positive := g_DATA_WIDTH / 8;

  type fsm_t is (S_SOP, S_DATA, S_LATE_EOP);

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
    state  : fsm_t;
    buf    : snk_data_i'subtype;
    shl    : natural range 0 to g_DATA_WIDTH / 8;
    lead   : snk_data_i'subtype;
    ready  : std_logic;
    is_sop : std_logic;
    avst   : avst_t;
  end record sig_t;

  constant c_FSM_INIT : sig_t :=
  (
    state  => S_SOP,
    buf    => (others => '0'),
    shl    => 0,
    lead   => (others => '0'),
    ready  => '0',
    is_sop => '0',
    avst   => c_AVST_INIT
  );
  signal   rreg       : sig_t := c_FSM_INIT;
  signal   rcmb       : sig_t;
  signal   skid       : avst_t;

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

      when S_SOP =>
        -- incoming packet and source is ready
        if (v_int.ready = '1' and skid.sop = '1' and skid.valid = '1') then
          v_int.shl        := to_integer(shl_i);
          v_int.avst.sop   := skid.sop;
          v_int.avst.eop   := skid.eop;
          v_int.avst.valid := skid.valid;
          v_int.avst.empty := skid.empty;

          for i in 0 to g_DATA_WIDTH / 8 loop
            if (i = v_int.shl) then
              v_int.lead := skid.data(skid.data'left downto skid.data'length - i * 8) &
                (skid.data'left downto i * 8 => '0');
              v_int.buf  := skid.data(g_DATA_WIDTH - i * 8 - 1 downto 0) & (i * 8 - 1 downto 0 => '0');
            end if;
          end loop;

          if (skid.eop = '0') then
            -- multi word packet
            v_int.is_sop     := '1';
            v_int.avst.sop   := '0';
            v_int.avst.eop   := '0';
            v_int.avst.valid := '0';
            v_int.state      := S_DATA;
          elsif (v_int.shl < g_DATA_WIDTH / 8 - to_integer(skid.empty)) then
            v_int.avst.data  := v_int.buf;
            v_int.avst.empty := to_unsigned(to_integer(skid.empty) + v_int.shl, skid.empty'length);
          end if;
        end if;

      when S_DATA =>

        if (skid.valid = '1' and v_int.ready = '1') then
          v_int.is_sop     := '0';
          v_int.avst.sop   := rreg.is_sop;
          v_int.avst.eop   := skid.eop;
          v_int.avst.valid := skid.valid;
          v_int.avst.empty := skid.empty;

          for i in 0 to g_DATA_WIDTH / 8 loop
            if (i = v_int.shl) then
              v_int.avst.data := rreg.buf(rreg.buf'left downto i * 8) &
                skid.data(skid.data'left downto skid.data'length - i * 8);
              v_int.buf       := skid.data(g_DATA_WIDTH - i * 8 - 1 downto 0) & (i * 8 - 1 downto 0 => '0');
            end if;
          end loop;

          -- during packet
          if (skid.eop = '1') then
            -- need a second word for eop
            if (v_int.shl + to_integer(skid.empty) < g_DATA_WIDTH / 8) then
              v_int.avst.empty := to_unsigned(v_int.shl + to_integer(skid.empty), skid.empty'length);
              v_int.avst.eop   := '0';
              v_int.state      := S_LATE_EOP;
            else
              v_int.avst.empty := to_unsigned(to_integer(skid.empty) + v_int.shl - g_DATA_WIDTH / 8, skid.empty'length);
              v_int.state      := S_SOP;
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
          v_int.state      := S_SOP;
        end if;

        v_int.ready := '0';

    end case;

    if (reset_i = '1') then
      v_int := c_FSM_INIT;
    end if;

    rcmb <= v_int;

  end process proc_fsm;

  rreg <= rcmb when rising_edge(clk_i);

  src_head_o <= rreg.lead when src_sop_o else
                (others => '0');

  src_sop_o   <= rreg.avst.sop;
  src_eop_o   <= rreg.avst.eop;
  src_valid_o <= rreg.avst.valid;
  src_empty_o <= rreg.avst.empty;
  src_data_o  <= rreg.avst.data;

end architecture rtl;
