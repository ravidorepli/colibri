--! @file cc_fifo.vhdl
--! @brief Dual Clock FIFO
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 13-05-2024 Created
--! @version 0.5
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.encoders.all;

--==================================================================================================
--! @brief Dual Clock FIFO
--! @details
--!
--! This component implements the FIFO logic with dual clock crossing.
--! This generic FIFO implement mixed width support (different input and output width).
--! A peek feature is available to get the next word to be read out on the write side.
--!
--! @details
--! 0.5 add peek port to get the next word to be read
--! 0.4 generalized interface to support mixed data width
--! 0.3 add synchro modules
--! 0.2 add first word fall through (lookahead, streaming)
--! 0.1 initial release
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity cc_fifo is
  generic (
    --! number of words to store (in case of mixed widths, the stored width is maximum of the two)
    g_NUM_WORDS    : positive := 4;
    --! size of input words in bits
    g_INPUT_WIDTH  : positive := 8;
    --! size of output words in bits
    --! (0 = g_INPUT_WIDTH: Quartus Lite / Standard reject a default taken from another generic)
    g_OUTPUT_WIDTH : natural  := 0;
    --! enable first word fall through (or lookahead, or streaming)
    g_ENABLE_FWFT  : boolean  := false;
    --! Peek on next data word to read on write clock
    g_PEEK_NEXT    : boolean  := false
  );
  port (
    reset_i     : in    std_logic;                                     --! asynchronous reset
    wrclk_i     : in    std_logic;                                     --! write clock
    rdclk_i     : in    std_logic;                                     --! read clock
    data_i      : in    std_logic_vector(g_INPUT_WIDTH - 1 downto 0);  --! data_i input on write clock
    wrreq_i     : in    std_logic;                                     --! write request on write clock
    rdreq_i     : in    std_logic;                                     --! read request on read clock
    q_o         : out   std_logic_vector(or_default(g_OUTPUT_WIDTH, g_INPUT_WIDTH) - 1 downto 0); --! data_i output on read clock
    wrusedw_o   : out   unsigned(log2ceil(g_NUM_WORDS) - 1 downto 0);  --! number of words used on write clock
    rdusedw_o   : out   unsigned(log2ceil(g_NUM_WORDS) - 1 downto 0);  --! number of words used on read clock
    wrempty_o   : out   std_logic;                                     --! empty signal on write clock
    wrfull_o    : out   std_logic;                                     --! full signal on write clock
    rdempty_o   : out   std_logic;                                     --! empty signal on read clock
    rdfull_o    : out   std_logic;                                     --! full signal on read clock
    wrq_o       : out   std_logic_vector(g_INPUT_WIDTH - 1 downto 0);  --! peek next data word to read on write clock
    wrq_valid_o : out   std_logic                                      --! valid signal for peek data on write clock
  );
end entity cc_fifo;

architecture rtl of cc_fifo is

  constant c_OUTPUT_WIDTH : positive := or_default(g_OUTPUT_WIDTH, g_INPUT_WIDTH);

  -- Width in bits of the words stored in the FIFO
  constant c_FIFO_WIDTH : positive := max_int(g_INPUT_WIDTH, c_OUTPUT_WIDTH);

  -- cc_fifo memory storage

  type mem_t is array (0 to g_NUM_WORDS - 1) of std_logic_vector(c_FIFO_WIDTH - 1 downto 0);

  signal memory : mem_t;

  -- write interface signals
  signal data_in : std_logic_vector(c_FIFO_WIDTH - 1 downto 0);
  signal wrreq   : std_logic;
  signal wrfull  : std_logic;

  -- read interface signals
  signal data_out : std_logic_vector(c_FIFO_WIDTH - 1 downto 0);
  signal rdreq    : std_logic;
  signal rdempty  : std_logic;

  -- memory pointers
  signal wr_ptr,       rd_ptr       : natural range 0 to g_NUM_WORDS - 1 := 0;
  signal rwr_ptr,      wrd_ptr      : natural range 0 to g_NUM_WORDS - 1 := 0;
  signal wr_ptr_gray,  rd_ptr_gray  : std_logic_vector(log2ceil(g_NUM_WORDS) - 1 downto 0);
  signal rwr_ptr_gray, wrd_ptr_gray : std_logic_vector(log2ceil(g_NUM_WORDS) - 1 downto 0);
  signal int_rusedw                 : natural range 0 to g_NUM_WORDS     := 0;
  signal int_wusedw                 : natural range 0 to g_NUM_WORDS     := 0;

  -- internal request with overflow and underflow safety
  signal wr_safe,      rd_safe : std_logic;
  -- signals for FWFT generate
  signal int_empty             : std_logic;
  signal int_rdreq             : std_logic;

  -- synchronized reset signals
  signal wr_reset,     rd_reset : std_logic;

begin

  ------------------------------------------------------------------------------
  -- Reset synchronization
  ------------------------------------------------------------------------------
  -- synchronize `reset_i` to write domain
  wr_synchro_reset : entity work.synchro_reset
    generic map (
      g_IN_POLARITY  => '1',
      g_OUT_POLARITY => '1',
      g_DURATION     => 1
    )
    port map (
      clk_i   => wrclk_i,
      reset_i => reset_i,
      reset_o => wr_reset
    );

  -- synchronize `reset_i` to read domain
  rd_synchro_reset : entity work.synchro_reset
    generic map (
      g_IN_POLARITY  => '1',
      g_OUT_POLARITY => '1',
      g_DURATION     => 1
    )
    port map (
      clk_i   => rdclk_i,
      reset_i => reset_i,
      reset_o => rd_reset
    );

  ------------------------------------------------------------------------------
  -- Input width conversion
  ------------------------------------------------------------------------------
  gen_up_conversion : if g_INPUT_WIDTH < c_OUTPUT_WIDTH generate
    signal gbx_ready : std_logic;
  begin

    gearbox_inst : entity colibri.gearbox
      generic map (
        g_INPUT_WIDTH  => g_INPUT_WIDTH,
        g_OUTPUT_WIDTH => c_OUTPUT_WIDTH
      )
      port map (
        clk_i       => wrclk_i,
        reset_i     => wr_reset,
        snk_data_i  => data_i,
        snk_valid_i => wrreq_i,
        snk_ready_o => gbx_ready,
        src_data_o  => data_in,
        src_valid_o => wrreq,
        src_ready_i => not wrfull
      );

    wrfull_o <= not gbx_ready;

  else generate
    data_in  <= data_i;
    wrreq    <= wrreq_i;
    wrfull_o <= wrfull or wr_reset;

  end generate gen_up_conversion;

  ------------------------------------------------------------------------------
  -- Clock Crossing FIFO
  ------------------------------------------------------------------------------

  -- overflow and underflow safety
  wr_safe <= wrreq and not wrfull;
  rd_safe <= int_rdreq and not int_empty;

  -- clock crossing with gray pointers to avoid metastability
  -- add register after gray conversion to ensure correct cdc
  wr_ptr_gray <= bin2gray(wr_ptr, g_NUM_WORDS) when rising_edge(wrclk_i);
  rd_ptr_gray <= bin2gray(rd_ptr, g_NUM_WORDS) when rising_edge(rdclk_i);
  rwr_ptr     <= gray2bin(rwr_ptr_gray);
  wrd_ptr     <= gray2bin(wrd_ptr_gray);

  wr_ptr_synchro : entity work.synchro
    generic map (
      g_DATA_LENGTH => log2ceil(g_NUM_WORDS),
      g_NUM_STAGES  => 2
    )
    port map (
      clk_i   => rdclk_i,
      reset_i => rd_reset,
      data_i  => wr_ptr_gray,
      data_o  => rwr_ptr_gray
    );

  rd_ptr_synchro : entity work.synchro
    generic map (
      g_DATA_LENGTH => log2ceil(g_NUM_WORDS),
      g_NUM_STAGES  => 2
    )
    port map (
      clk_i   => wrclk_i,
      reset_i => wr_reset,
      data_i  => rd_ptr_gray,
      data_o  => wrd_ptr_gray
    );

  --! keep count of used words
  int_wusedw <= g_NUM_WORDS + wr_ptr - wrd_ptr when wr_ptr < wrd_ptr else
                wr_ptr - wrd_ptr;
  wrusedw_o  <= to_unsigned(int_wusedw, wrusedw_o'length);

  int_rusedw <= g_NUM_WORDS + rwr_ptr - rd_ptr when rwr_ptr < rd_ptr else
                rwr_ptr - rd_ptr;
  rdusedw_o  <= to_unsigned(int_rusedw, rdusedw_o'length);

  -- drive full and empty signals
  wrfull    <= '1' when int_wusedw = g_NUM_WORDS - 1 else
               '0';
  rdfull_o  <= '1' when int_rusedw = g_NUM_WORDS - 1 else
               '0';
  int_empty <= '1' when int_rusedw = 0 else
               '0';

  empty_sync_inst : entity colibri.synchro
    generic map (
      g_DATA_LENGTH => 1,
      g_INIT_VALUE  => "1"
    )
    port map (
      clk_i     => wrclk_i,
      reset_i   => wr_reset,
      data_i(0) => rdempty_o,
      data_o(0) => wrempty_o
    );

  --! write pointer logic
  proc_wr_ptr : process (wrclk_i) is
  begin

    if rising_edge(wrclk_i) then
      if (wr_reset = '1') then
        wr_ptr <= 0;
      else
        if (wr_safe = '1') then
          if (wr_ptr = g_NUM_WORDS - 1) then
            wr_ptr <= 0;
          else
            wr_ptr <= wr_ptr + 1;
          end if;
        end if;
      end if;
    end if;

  end process proc_wr_ptr;

  --! read pointer logic
  proc_rd_ptr : process (rdclk_i) is
  begin

    if rising_edge(rdclk_i) then
      if (rd_reset = '1') then
        rd_ptr <= 0;
      else
        if (rd_safe = '1') then
          if (rd_ptr = g_NUM_WORDS - 1) then
            rd_ptr <= 0;
          else
            rd_ptr <= rd_ptr + 1;
          end if;
        end if;
      end if;
    end if;

  end process proc_rd_ptr;

  --! write data to cc_fifo
  proc_data_write : process (wrclk_i) is
  begin

    if rising_edge(wrclk_i) then
      if (wr_reset = '0' and wr_safe = '1') then
        memory(wr_ptr) <= data_in;
      end if;
    end if;

  end process proc_data_write;

  -- read data from cc_fifo
  proc_data_read : process (rdclk_i) is
  begin

    if rising_edge(rdclk_i) then
      if (rd_reset = '0' and rd_safe = '1') then
        data_out <= memory(rd_ptr);
      end if;
    end if;

  end process proc_data_read;

  ------------------------------------------------------------------------------
  -- Peek on Write logic (only available when input and output widths are the same)
  ------------------------------------------------------------------------------
  gen_peek_write : if g_PEEK_NEXT and g_INPUT_WIDTH = c_OUTPUT_WIDTH generate

    type sig_t is record
      ptr    : natural range 0 to g_NUM_WORDS - 1;
      enable : std_logic;
      q      : std_logic_vector(wrq_o'range);
      fwft   : std_logic_vector(wrq_o'range);
      valid  : std_logic;
    end record sig_t;

    constant c_SIG_INIT : sig_t :=
    (
      ptr    => 0,
      enable => '0',
      q      => (others => '0'),
      fwft   => (others => '0'),
      valid  => '0'
    );

    signal rreg : sig_t;
    signal rcmb : sig_t;
  begin
    -- peek data from cc_fifo
    proc_peek_logic : process (all) is

      variable v_int : sig_t;

    begin

      v_int := rreg;

      v_int.ptr := wrd_ptr;

      -- check read ptr updates and not empty
      if ((rreg.ptr /= wrd_ptr) and (wr_ptr /= wrd_ptr)) then
        v_int.valid := '1';
        v_int.q     := memory(wrd_ptr);
      -- direct sampling when empty
      elsif (int_wusedw = 0 and wr_safe = '1') then
        v_int.valid := '1';
        v_int.q     := data_i;
      else
        v_int.valid := '0';
      end if;

      -- handle FWFT logic
      if (g_ENABLE_FWFT) then
        if (rreg.valid) then
          v_int.fwft   := rreg.q;
          v_int.enable := '1'; -- discard first register value when empty
        end if;
      end if;

      if (wr_reset) then
        v_int := c_SIG_INIT;
      end if;

      rcmb <= v_int;

    end process proc_peek_logic;

    rreg <= rcmb when rising_edge(wrclk_i);

    -- handle the extra output register logic
    gen_fwft : if g_ENABLE_FWFT generate
    begin

      proc_fwft : process (wrclk_i) is
      begin

        if rising_edge(wrclk_i) then
          if (rreg.valid) then
            wrq_valid_o <= rreg.enable;
            wrq_o       <= rreg.fwft;
          else
            wrq_valid_o <= '0';
            wrq_o       <= (others => '0');
          end if;
        end if;

      end process proc_fwft;

    else generate
      wrq_valid_o <= rreg.valid;
      wrq_o       <= rreg.q;
    end generate gen_fwft;

  end generate gen_peek_write;

  ------------------------------------------------------------------------------
  -- First Word Fall Through logic
  ------------------------------------------------------------------------------
  gen_stream_fifo : if g_ENABLE_FWFT or g_INPUT_WIDTH > c_OUTPUT_WIDTH generate
    signal reg_valid : std_logic;
    signal cmb_valid : std_logic;
  begin
    -- convert fifo to streaming mode

    proc_fifo_stream_cmb : process (all) is

      variable v_valid : std_logic;

    begin

      v_valid := reg_valid;

      if (rdreq = '1' and reg_valid = '1') then
        v_valid := '0';
      end if;

      if (int_empty = '0' and v_valid = '0') then
        int_rdreq <= '1';
        v_valid   := '1';
      else
        int_rdreq <= '0';
      end if;

      if (rd_reset) then
        v_valid := '0';
      end if;

      cmb_valid <= v_valid;

    end process proc_fifo_stream_cmb;

    reg_valid <= cmb_valid when rising_edge(rdclk_i);
    rdempty   <= not reg_valid;

  else generate
    int_rdreq <= rdreq;
    rdempty   <= int_empty;

  end generate gen_stream_fifo;

  ------------------------------------------------------------------------------
  -- Output width conversion
  ------------------------------------------------------------------------------
  gen_down_conversion : if g_INPUT_WIDTH > c_OUTPUT_WIDTH generate
    signal gbx_valid    : std_logic;
    signal gbx_data_out : std_logic_vector(q_o'range);
  begin

    gearbox_inst : entity colibri.gearbox
      generic map (
        g_INPUT_WIDTH  => g_INPUT_WIDTH,
        g_OUTPUT_WIDTH => c_OUTPUT_WIDTH
      )
      port map (
        clk_i       => rdclk_i,
        reset_i     => rd_reset,
        snk_data_i  => data_out,
        snk_valid_i => not rdempty,
        snk_ready_o => rdreq,
        src_data_o  => gbx_data_out,
        src_valid_o => gbx_valid,
        src_ready_i => rdreq_i
      );

    rdempty_o <= not gbx_valid;

    -- Generate additional output delay in case First Word Fall Through is disabled
    gen_output_delay : if g_ENABLE_FWFT generate
      q_o <= gbx_data_out;
    else generate
      q_o <= gbx_data_out when rising_edge(rdclk_i);
    end generate gen_output_delay;

  else generate
    q_o       <= data_out;
    rdempty_o <= rdempty;
    rdreq     <= rdreq_i;

  end generate gen_down_conversion;

end architecture rtl;
