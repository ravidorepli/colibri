--! @title Dual Clock Packet FIFO
--! @file packet_cc_fifo.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 03-07-2024
--! @version 0.3

--! @details
--! 0.3 add size calculation option
--! 0.2 add synchro modules
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
  use colibri.encoders.all;

entity packet_cc_fifo is
  generic (

    --! packet maximum size in bytes
    g_MAX_PACKET_BYTES  : positive := 256;
    --! number of packets to store
    g_NUM_PACKETS       : positive := 4;
    --! used packets port bits
    g_USEDP_BITS        : positive := log2ceil(g_NUM_PACKETS);
    --! enable packet size counting
    g_ENABLE_SIZE_COUNT : boolean  := true;
    --! packet size port width
    g_PKT_SIZE_BITS     : positive := log2ceil(g_MAX_PACKET_BYTES) + 1;
    --! size of words in bits
    g_DATA_WIDTH        : positive := 8
  );
  port (
    wrclk_i     : in    std_logic;                                     --! snk clock
    reset_i     : in    std_logic;                                     --! reset_i on the snk clock
    rdclk_i     : in    std_logic;                                     --! src clock
    --! fifo status ports
    wrusedp_o   : out   unsigned(log2ceil(g_USEDP_BITS) - 1 downto 0); --! number of words used on write clock
    rdusedp_o   : out   unsigned(log2ceil(g_USEDP_BITS) - 1 downto 0); --! number of words used on read clock
    wrempty_o   : out   std_logic;                                     --! empty signal on write clock
    wrfull_o    : out   std_logic;                                     --! full signal on write clock
    rdempty_o   : out   std_logic;                                     --! empty signal on read clock
    rdfull_o    : out   std_logic;                                     --! full signal on read clock
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
end entity packet_cc_fifo;

architecture rtl of packet_cc_fifo is

  constant c_PACKET_WORDS : natural := div_ceil(g_MAX_PACKET_BYTES * 8, g_DATA_WIDTH);

  --
  type record_t is record
    sop   : std_logic;
    eop   : std_logic;
    empty : unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);
    data  : std_logic_vector(g_DATA_WIDTH - 1 downto 0);
  end record record_t;

  constant c_RECORD_INIT : record_t :=
  (
    sop   => '0',
    eop   => '0',
    empty => (others => '0'),
    data  => (others => '0')
  );

  constant c_RECORD_BITS : natural := 1 + 1 + g_DATA_WIDTH + log2ceil(g_DATA_WIDTH / 8);

  signal rsnk        : record_t;
  signal rsrc        : record_t;
  signal snk_rec_slv : std_logic_vector(c_RECORD_BITS - 1 downto 0);
  signal src_rec_slv : std_logic_vector(c_RECORD_BITS - 1 downto 0);

  -- fifo signals
  signal fifo_empty : std_logic;
  signal fifo_full  : std_logic;
  signal fifo_wreq  : std_logic;

  -- memory pointers
  signal wr_ptr,       rd_ptr       : natural range 0 to g_NUM_PACKETS - 1 := 0;
  signal rwr_ptr,      wrd_ptr      : natural range 0 to g_NUM_PACKETS - 1 := 0;
  signal wr_ptr_gray,  rd_ptr_gray  : std_logic_vector(log2ceil(g_NUM_PACKETS) - 1 downto 0);
  signal rwr_ptr_gray, wrd_ptr_gray : std_logic_vector(log2ceil(g_NUM_PACKETS) - 1 downto 0);
  signal int_rusedp                 : natural range 0 to g_NUM_PACKETS     := 0;
  signal int_wusedp                 : natural range 0 to g_NUM_PACKETS     := 0;

  -- synchronized reset signal
  signal src_reset : std_logic;
  -- size calculation signals
  signal int_size  : std_logic_vector(log2ceil(g_MAX_PACKET_BYTES) downto 0);

  -- fsm signals

  type sig_t is record
    count   : natural range 0 to g_NUM_PACKETS;
    wreq    : std_logic;
    rreq    : std_logic;
    ready   : std_logic;
    valid   : std_logic;
    orecord : record_t;
  end record sig_t;

  signal rreg,         rcmb : sig_t;

  constant c_SIG_INIT : sig_t :=
  (
    count   => 0,
    wreq    => '0',
    rreq    => '0',
    ready   => '0',
    valid   => '0',
    orecord => c_RECORD_INIT
  );

  -- conversion functions
  function record_to_slv (arg : record_t) return std_logic_vector is

    variable v_res : std_logic_vector(c_RECORD_BITS - 1 downto 0);

  begin

    v_res := arg.sop & arg.eop & std_logic_vector(arg.empty) & arg.data;
    return v_res;

  end function record_to_slv;

  function slv_to_record (arg : std_logic_vector(c_RECORD_BITS - 1 downto 0)) return record_t is

    variable v_res : record_t;

  begin

    v_res.sop   := arg(arg'left);
    v_res.eop   := arg(arg'left - 1);
    v_res.empty := unsigned(arg(arg'left - 2 downto g_DATA_WIDTH));
    v_res.data  := arg(g_DATA_WIDTH - 1 downto 0);
    return v_res;

  end function slv_to_record;

begin

  -- synchronize `reset_i` to source domain
  wr_synchro_reset : entity work.synchro_reset
    generic map (
      g_IN_POLARITY  => '1',
      g_OUT_POLARITY => '1',
      g_DURATION     => 1
    )
    port map (
      clk_i   => rdclk_i,
      reset_i => reset_i,
      reset_o => src_reset
    );

  -- clock crossing with gray pointers to avoid metastability
  -- add register after gray conversion to ensure correct cdc
  wr_ptr_gray <= bin2gray(wr_ptr, g_NUM_PACKETS) when rising_edge(wrclk_i);
  rd_ptr_gray <= bin2gray(rd_ptr, g_NUM_PACKETS) when rising_edge(rdclk_i);
  rwr_ptr     <= gray2bin(rwr_ptr_gray);
  wrd_ptr     <= gray2bin(wrd_ptr_gray);

  wr_ptr_synchro : entity work.synchro
    generic map (
      g_DATA_LENGTH => log2ceil(g_NUM_PACKETS),
      g_NUM_STAGES  => 2
    )
    port map (
      clk_i   => rdclk_i,
      reset_i => src_reset,
      data_i  => wr_ptr_gray,
      data_o  => rwr_ptr_gray
    );

  rd_ptr_synchro : entity work.synchro
    generic map (
      g_DATA_LENGTH => log2ceil(g_NUM_PACKETS),
      g_NUM_STAGES  => 2
    )
    port map (
      clk_i   => wrclk_i,
      reset_i => reset_i,
      data_i  => rd_ptr_gray,
      data_o  => wrd_ptr_gray
    );

  --! keep count of used words
  int_wusedp <= g_NUM_PACKETS + wr_ptr - wrd_ptr when wr_ptr < wrd_ptr else
                wr_ptr - wrd_ptr;
  wrusedp_o  <= to_unsigned(int_wusedp, wrusedp_o'length);

  int_rusedp <= g_NUM_PACKETS + rwr_ptr - rd_ptr when rwr_ptr < rd_ptr else
                rwr_ptr - rd_ptr;
  rdusedp_o  <= to_unsigned(int_rusedp, rdusedp_o'length);
  -- drive full and empty signals
  wrfull_o  <= '1' when int_wusedp = g_NUM_PACKETS - 1 else
               '0';
  wrempty_o <= '1' when int_wusedp = 0 else
               '0';
  rdfull_o  <= '1' when int_rusedp = g_NUM_PACKETS - 1 else
               '0';
  rdempty_o <= '1' when int_rusedp = 0 else
               '0';
  -- map to record and single vector
  rsnk.sop    <= snk_sop_i;
  rsnk.eop    <= snk_eop_i;
  rsnk.empty  <= snk_empty_i;
  rsnk.data   <= snk_data_i;
  snk_rec_slv <= record_to_slv(rsnk);

  -- drive snk_ready signal
  snk_ready_o <= '1' when fifo_full = '0' and wrfull_o = '0' else
                 '0';
  -- drive write requests
  fifo_wreq <= snk_valid_i and snk_ready_o;

  -- count packets written
  proc_cnt_packets : process (wrclk_i) is
  begin

    if rising_edge(wrclk_i) then
      if (reset_i = '1') then
        wr_ptr <= 0;
      else
        if (fifo_wreq and rsnk.eop) then
          if (wr_ptr = g_NUM_PACKETS - 1) then
            wr_ptr <= 0;
          else
            wr_ptr <= wr_ptr + 1;
          end if;
        end if;
      end if;
    end if;

  end process proc_cnt_packets;

  cc_fifo_inst : entity work.cc_fifo
    generic map (
      g_NUM_WORDS    => c_PACKET_WORDS * g_NUM_PACKETS,
      g_INPUT_WIDTH  => c_RECORD_BITS,
      g_OUTPUT_WIDTH => c_RECORD_BITS,
      g_ENABLE_FWFT  => true
    )
    port map (
      wrclk_i   => wrclk_i,
      reset_i   => reset_i,
      rdclk_i   => rdclk_i,
      data_i    => snk_rec_slv,
      wrreq_i   => fifo_wreq,
      rdreq_i   => rcmb.rreq,
      q_o       => src_rec_slv,
      wrusedw_o => open,
      rdusedw_o => open,
      wrempty_o => open,
      wrfull_o  => fifo_full,
      rdempty_o => fifo_empty,
      rdfull_o  => open
    );

  gen_size_count_fifo : if g_ENABLE_SIZE_COUNT generate
    signal cmb_size : unsigned(log2ceil(g_MAX_PACKET_BYTES) downto 0);
    signal reg_size : unsigned(log2ceil(g_MAX_PACKET_BYTES) downto 0);
  begin

    proc_size_cnt_cmb : process (all) is

      variable v_int : cmb_size'subtype;

    begin

      v_int := reg_size;

      if (snk_valid_i and snk_ready_o) then
        if (snk_sop_i = '1') then
          v_int := (others => '0');
        end if;
        v_int := v_int + g_DATA_WIDTH / 8;
        if (snk_eop_i = '1') then
          v_int := v_int - snk_empty_i;
        end if;
      end if;

      cmb_size <= v_int;

    end process proc_size_cnt_cmb;

    reg_size <= cmb_size when rising_edge(wrclk_i);

    size_fifo_inst : entity colibri.cc_fifo
      generic map (
        g_NUM_WORDS    => g_NUM_PACKETS,
        g_INPUT_WIDTH  => int_size'length,
        g_OUTPUT_WIDTH => int_size'length,
        g_ENABLE_FWFT  => true
      )
      port map (
        wrclk_i   => wrclk_i,
        reset_i   => reset_i,
        rdclk_i   => rdclk_i,
        data_i    => std_logic_vector(cmb_size),
        wrreq_i   => fifo_wreq and snk_eop_i,
        rdreq_i   => rcmb.rreq and rsrc.sop,
        q_o       => int_size,
        wrusedw_o => open,
        rdusedw_o => open,
        wrempty_o => open,
        wrfull_o  => open,
        rdempty_o => open,
        rdfull_o  => open
      );

  else generate
    int_size <= (others => '0');
  end generate gen_size_count_fifo;

  rsrc <= slv_to_record(src_rec_slv);

  rreg <= rcmb when rising_edge(rdclk_i);

  proc_read_logic : process (all) is

    variable v_int : sig_t;

  begin

    v_int      := rreg;
    v_int.rreq := '0';

    -- ack stream read
    if (src_ready_i = '1' and rreg.valid = '1') then
      v_int.valid := '0';
    end if;

    -- read from fifo
    if (v_int.valid = '0' and fifo_empty = '0' and rdempty_o = '0') then
      v_int.rreq    := '1';
      v_int.valid   := '1';
      v_int.orecord := rsrc;
      if (rsrc.eop = '1') then
        if (rd_ptr = g_NUM_PACKETS - 1) then
          v_int.count := 0;
        else
          v_int.count := rreg.count + 1;
        end if;
      end if;
    end if;

    if (src_reset) then
      v_int := c_SIG_INIT;
    end if;

    rcmb <= v_int;

  end process proc_read_logic;

  -- drive signals
  rd_ptr      <= rreg.count;
  src_sop_o   <= rreg.orecord.sop;
  src_eop_o   <= rreg.orecord.eop;
  src_empty_o <= rreg.orecord.empty;
  src_data_o  <= rreg.orecord.data;
  src_valid_o <= rreg.valid;
  src_size_o  <= resize(unsigned(int_size), g_PKT_SIZE_BITS) when rreg.valid = '1' else
                 (others => '0');

end architecture rtl;
