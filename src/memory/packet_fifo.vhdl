--! @title Single Clock Packet FIFO
--! @file packet_fifo.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 03-07-2024
--! @version 0.2

--! @details
--! 0.2 add size calculation option
--! 0.1 initial release
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

entity packet_fifo is
  generic (

    --! packet maximum size in bytes
    g_MAX_PACKET_BYTES  : positive := 256;
    --! number of packets to store
    g_NUM_PACKETS       : positive := 4;
    --! used packets port bits
    g_USEDP_BITS        : positive := log2ceil(g_NUM_PACKETS) + 1;
    --! enable packet size counting
    g_ENABLE_SIZE_COUNT : boolean  := true;
    --! packet size port width
    g_PKT_SIZE_BITS     : positive := log2ceil(g_MAX_PACKET_BYTES) + 1;
    --! size of words in bits
    g_DATA_WIDTH        : positive := 8
  );
  port (
    clk_i       : in    std_logic; --! common clock
    reset_i     : in    std_logic; --! reset_i
    --! fifo status ports
    full_o      : out   std_logic;
    empty_o     : out   std_logic;
    usedp_o     : out   unsigned(g_USEDP_BITS - 1 downto 0);
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
    src_size_o  : out   unsigned(g_PKT_SIZE_BITS - 1 downto 0)
  --! @end
  );
end entity packet_fifo;

architecture rtl of packet_fifo is

  constant c_PACKET_WORDS : natural := div_ceil(g_MAX_PACKET_BYTES * 8, g_DATA_WIDTH);

  subtype avst_m_t is avst_master_t(
    data(g_DATA_WIDTH - 1 downto 0),
    empty(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0)
  );

  --

  constant c_RECORD_BITS : natural := 1 + 1 + g_DATA_WIDTH + log2ceil(g_DATA_WIDTH / 8);

  signal rsnk        : avst_m_t;
  signal rsrc        : avst_m_t;
  signal snk_rec_slv : std_logic_vector(c_RECORD_BITS - 1 downto 0);
  signal src_rec_slv : std_logic_vector(c_RECORD_BITS - 1 downto 0);

  -- packet fifo signals
  signal empty : std_logic;
  signal full  : std_logic;

  -- size calculation signals
  signal int_size : std_logic_vector(log2ceil(g_MAX_PACKET_BYTES) downto 0);
  -- fsm signals

  type sig_t is record
    pcount  : natural range 0 to g_NUM_PACKETS;
    wreq    : std_logic;
    size    : unsigned(int_size'range);
    rreq    : std_logic;
    ready   : std_logic;
    valid   : std_logic;
    orecord : avst_m_t;
  end record sig_t;

  signal rreg, rcmb : sig_t;

  constant c_SIG_INIT : sig_t :=
  (
    pcount  => 0,
    wreq    => '0',
    size    => (others => '0'),
    rreq    => '0',
    ready   => '0',
    valid   => '0',
    orecord => avst_master_init(g_DATA_WIDTH)
  );

  -- conversion functions
  function record_to_slv (arg : avst_m_t) return std_logic_vector is

    variable v_res : std_logic_vector(c_RECORD_BITS - 1 downto 0);

  begin

    v_res := arg.sop & arg.eop & std_logic_vector(arg.empty) & arg.data;
    return v_res;

  end function record_to_slv;

  function slv_to_record (arg : std_logic_vector(c_RECORD_BITS - 1 downto 0)) return avst_m_t is

    variable v_res : avst_m_t;

  begin

    v_res.sop   := arg(arg'left);
    v_res.eop   := arg(arg'left - 1);
    v_res.empty := unsigned(arg(arg'left - 2 downto g_DATA_WIDTH));
    v_res.data  := arg(g_DATA_WIDTH - 1 downto 0);
    return v_res;

  end function slv_to_record;

begin

  -- map to record and single vector
  rsnk.sop    <= snk_sop_i;
  rsnk.eop    <= snk_eop_i;
  rsnk.empty  <= snk_empty_i;
  rsnk.data   <= snk_data_i;
  snk_rec_slv <= record_to_slv(rsnk);

  rsrc <= slv_to_record(src_rec_slv);

  packet_fifo_inst : entity colibri.fifo
    generic map (
      g_NUM_WORDS    => c_PACKET_WORDS * g_NUM_PACKETS,
      g_INPUT_WIDTH  => c_RECORD_BITS,
      g_OUTPUT_WIDTH => c_RECORD_BITS,
      g_ENABLE_FWFT  => true
    )
    port map (
      clk_i   => clk_i,
      reset_i => reset_i,
      data_i  => snk_rec_slv,
      wrreq_i => rcmb.wreq,
      rdreq_i => rcmb.rreq,
      q_o     => src_rec_slv,
      usedw_o => open,
      empty_o => empty,
      full_o  => full
    );

  gen_size_count_fifo : if g_ENABLE_SIZE_COUNT generate

    size_fifo_inst : entity colibri.fifo
      generic map (
        g_NUM_WORDS    => g_NUM_PACKETS,
        g_INPUT_WIDTH  => int_size'length,
        g_OUTPUT_WIDTH => int_size'length,
        g_ENABLE_FWFT  => false
      )
      port map (
        clk_i   => clk_i,
        reset_i => reset_i,
        data_i  => std_logic_vector(rcmb.size),
        wrreq_i => rcmb.wreq and snk_eop_i,
        rdreq_i => rcmb.rreq and rsrc.sop,
        q_o     => int_size,
        usedw_o => open,
        empty_o => open,
        full_o  => open
      );

  else generate
    int_size <= (others => '0');
  end generate gen_size_count_fifo;

  rreg <= rcmb when rising_edge(clk_i);

  proc_packet_fifo_logic : process (all) is

    variable v_int : sig_t;

  begin

    v_int       := rreg;
    v_int.wreq  := '0';
    v_int.ready := '0';
    v_int.rreq  := '0';
    -- if fifo is not full
    if (full = '0' and not (rreg.pcount = g_NUM_PACKETS)) then
      v_int.ready := '1';
    end if;

    -- write to fifo
    if (snk_valid_i = '1' and v_int.ready = '1') then
      v_int.wreq := '1';

      if (rsnk.sop = '1') then
        v_int.size := (others => '0');
      end if;
      v_int.size := v_int.size + g_DATA_WIDTH / 8;

      if (rsnk.eop = '1') then
        v_int.pcount := rreg.pcount + 1;
        v_int.size   := v_int.size - rsnk.empty;
      end if;
    end if;

    -- ack stream read
    if (src_ready_i = '1' and rreg.valid = '1') then
      v_int.valid := '0';
    end if;

    -- read from fifo
    if (v_int.valid = '0' and empty = '0' and rreg.pcount /= 0) then
      v_int.rreq    := '1';
      v_int.valid   := '1';
      v_int.orecord := rsrc;
      if (rsrc.eop = '1') then
        v_int.pcount := v_int.pcount - 1;
      end if;
    end if;

    if (reset_i) then
      v_int := c_SIG_INIT;
    end if;

    rcmb <= v_int;

  end process proc_packet_fifo_logic;

  -- drive signals
  full_o      <= not rcmb.ready;
  empty_o     <= '1' when rreg.pcount = 0 else
                 '0';
  usedp_o     <= to_unsigned(rreg.pcount, g_USEDP_BITS);
  snk_ready_o <= rcmb.ready;
  src_sop_o   <= rreg.orecord.sop;
  src_eop_o   <= rreg.orecord.eop;
  src_empty_o <= rreg.orecord.empty;
  src_data_o  <= rreg.orecord.data;
  src_size_o  <= resize(unsigned(int_size), g_PKT_SIZE_BITS) when rreg.valid = '1' else
                 (others => '0');
  src_valid_o <= rreg.valid;

end architecture rtl;
