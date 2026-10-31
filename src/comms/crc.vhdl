--! @title Cyclic Redundancy Check
--! @file crc.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 10-07-2025
--! @version 0.1

-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;
  use colibri.poly.all;

--==================================================================================================
--! @brief Cyclic Redundancy Check
--! @details
--!
--!  This entity implement a generic CRC calculator for a packeted stream.
--!  CRC value is outputed at the end-of-packet.
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity crc is
  generic (
    g_DATA_WIDTH : positive         := 64;    --! word size
    g_CRC_POLY   : std_logic_vector := c_CRC_8;
    g_INIT_VAL   : std_logic_vector := (g_CRC_POLY'range => '0');
    g_XOR_OUT    : std_logic_vector := (g_CRC_POLY'range => '0');
    g_INVERT_IN  : boolean          := false; --! invert bit order in input
    g_INVERT_OUT : boolean          := false  --! invert bit order in output
  );
  port (
    clk_i       : in    std_logic;
    reset_i     : in    std_logic;
    --! @virtualbus Avalon-ST @dir in sink
    snk_data_i  : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);       --! data input
    snk_sop_i   : in    std_logic;                                         --! start of packet
    snk_eop_i   : in    std_logic;                                         --! end of packet
    snk_empty_i : in    unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0); --! empty bytes
    snk_valid_i : in    std_logic;                                         --! input valid signal
    snk_ready_o : out   std_logic;                                         --! ready back pressure propagation
    --! @end
    --! @virtualbus Avalon-ST @dir out source
    src_data_o  : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0);       --! data output
    src_sop_o   : out   std_logic;                                         --! start of packet
    src_eop_o   : out   std_logic;                                         --! end of packet
    src_empty_o : out   unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0); --! empty bytes
    src_valid_o : out   std_logic;                                         --! valid output signal
    src_ready_i : in    std_logic;                                         --! source ready signal
    src_crc_o   : out   std_logic_vector(g_CRC_POLY'range)
  --! @end
  );
end entity crc;

architecture rtl of crc is

  constant c_DATA_BYTES    : natural := g_DATA_WIDTH / 8;
  constant c_CRC_WIDTH     : natural := g_CRC_POLY'length;
  constant c_BUF_WIDTH     : natural := g_DATA_WIDTH + c_CRC_WIDTH;
  constant c_CRC_OUT_WIDTH : natural := c_DATA_BYTES * c_CRC_WIDTH;

  subtype s_crc_range is natural range c_BUF_WIDTH - 1 downto g_DATA_WIDTH;

  subtype s_buf_range is natural range c_BUF_WIDTH - 1 downto 0;

  subtype s_data_range is natural range g_DATA_WIDTH  - 1 downto 0;

  --! generate crc linear equation system
  function gen_crc_lineq return slv_array_t is

    variable v_xor : std_logic;
    variable v_vec : std_logic_vector(s_BUF_RANGE) := (others => '0');
    --
    variable v_eqs : slv_array_t(0 to c_CRC_OUT_WIDTH - 1)(s_BUF_RANGE) := (others => (others => '0'));

  begin

    for b in v_vec'range loop

      for byte in 1 to c_DATA_BYTES loop
        v_vec    := (others => '0');
        v_vec(b) := '1';

        for s in 0 to (8 * byte) - 1 loop
          v_xor               := v_vec(v_vec'left) xor v_vec(g_DATA_WIDTH - 1);
          v_vec(s_crc_range)  := v_vec(c_BUF_WIDTH - 2 downto g_DATA_WIDTH) & '0';
          v_vec(s_data_range) := v_vec(g_DATA_WIDTH - 2 downto 0) & '0';

          if (v_xor) then
            v_vec(s_crc_range) := v_vec(s_crc_range) xor g_CRC_POLY;
          end if;

        end loop;

        for lineq in g_CRC_POLY'range loop
          v_eqs((c_DATA_BYTES - byte) * g_CRC_POLY'length + lineq)(b) := v_vec(g_DATA_WIDTH + lineq);
        end loop;

      end loop;

    end loop;

    return v_eqs;

  end function gen_crc_lineq;

  signal eqset : slv_array_t(0 to c_CRC_OUT_WIDTH - 1)(s_buf_range) := gen_crc_lineq;

  subtype avst_m_t is avst_master_t(
    data(snk_data_i'range),
    empty(snk_empty_i'range)
  );

  function invert_bit_in_bytes (vec : std_logic_vector) return std_logic_vector is

    variable v_res  : vec'subtype;
    variable v_byte : std_logic_vector(7 downto 0);

  begin

    for i in 0 to vec'length / 8 - 1 loop
      v_byte                              := vec(8 * (i + 1) - 1 downto 8 * i);
      v_res(8 * (i + 1) - 1 downto 8 * i) := invert_bit_order(v_byte);
    end loop;

    return v_res;

  end function invert_bit_in_bytes;

  type sig_t is record
    avst   : avst_m_t;
    crcset : std_logic_vector(c_CRC_OUT_WIDTH - 1 downto 0);
    crc    : std_logic_vector(g_CRC_POLY'range);
    ready  : std_logic;
  end record sig_t;

  constant c_AVST_INIT : avst_m_t :=
  (
    data  => (others => '0'),
    empty => (others => '0'),
    sop   => '0',
    eop   => '0',
    valid => '0'
  );

  constant c_FSM_INIT : sig_t :=
  (
    avst   => c_AVST_INIT,
    crcset => (others => '0'),
    crc    => (others => '0'),
    ready  => '0'
  );

  signal snk  : avst_m_t;
  signal skid : avst_m_t;
  signal src  : avst_m_t;
  signal rreg : sig_t := c_FSM_INIT;
  signal rcmb : sig_t;

  subtype last_crc_range is natural range c_CRC_WIDTH - 1 downto 0;

begin

  -- avst sink interface records

  snk.valid <= snk_valid_i;
  snk.sop   <= snk_sop_i;
  snk.eop   <= snk_eop_i;
  snk.data  <= invert_bit_in_bytes(snk_data_i) when g_INVERT_IN else
               snk_data_i;
  snk.empty <= snk_empty_i;

  -- skid for backpressure
  skid_buffer_inst : entity work.skid_buffer
    generic map (
      g_DATA_WIDTH => g_DATA_WIDTH
    )
    port map (
      clk_i       => clk_i,
      reset_i     => reset_i,
      snk_data_i  => snk.data,
      snk_empty_i => snk.empty,
      snk_sop_i   => snk.sop,
      snk_eop_i   => snk.eop,
      snk_valid_i => snk.valid,
      snk_ready_o => snk_ready_o,
      snk_keep_i  => (others => '0'),
      src_data_o  => skid.data,
      src_empty_o => skid.empty,
      src_sop_o   => skid.sop,
      src_eop_o   => skid.eop,
      src_valid_o => skid.valid,
      src_ready_i => rcmb.ready,
      src_keep_o  => open
    );

  -- avst source interface records
  src_valid_o <= rreg.avst.valid;
  src_sop_o   <= rreg.avst.sop;
  src_eop_o   <= rreg.avst.eop;
  -- de-reflect output
  src_data_o  <= invert_bit_in_bytes(rreg.avst.data) when g_INVERT_IN else
                 rreg.avst.data;
  src_empty_o <= rreg.avst.empty;
  src_crc_o   <= rreg.crc;

  proc_fsm : process (all) is

    variable v_int : sig_t;

  begin

    v_int := rreg;

    -- data is consumed
    if (rreg.avst.valid = '1' and src_ready_i = '1') then
      v_int.avst := c_AVST_INIT;
      v_int.crc  := (others => '0');
      if (rreg.avst.eop = '1') then
        v_int.crcset(last_crc_range) := g_INIT_VAL;
      end if;
    end if;

    v_int.ready := not v_int.avst.valid;

    if (v_int.ready and skid.valid) then
      v_int.avst := skid;
      -- calculate crc
      for i in 0 to c_CRC_OUT_WIDTH - 1 loop
        v_int.crcset(i) := xorvec((rreg.crcset(last_crc_range) & skid.data) and
                                  eqset(i));
      end loop;

      if (skid.eop = '1') then
        v_int.crc := v_int.crcset(c_CRC_WIDTH * (to_integer(skid.empty) + 1) - 1 downto
                                  c_CRC_WIDTH * (to_integer(skid.empty)));

        -- invert if required
        if (g_INVERT_OUT) then
          v_int.crc := invert_bit_order(v_int.crc);
        end if;

        -- xor the output
        v_int.crc := v_int.crc xor g_XOR_OUT;
      end if;
    end if;

    if (reset_i) then
      v_int.avst := c_AVST_INIT;
    end if;

    rcmb <= v_int;

  end process proc_fsm;

  rreg <= rcmb when rising_edge(clk_i);

end architecture rtl;
