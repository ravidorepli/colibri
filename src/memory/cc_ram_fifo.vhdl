--! @file cc_ram_fifo.vhdl
--! @brief Dual Clock RAM-based FIFO
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 05-03-2026 Created
--! @version 0.1
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
--! @brief Dual Clock RAM-based FIFO
--! @details
--!
--! This component implements the FIFO logic around a `single_dpram` entity.
--! This solution can help to optimize resource utilization wrt the more generic `cc_fifo`.
--! If mixed width is used, the code will try to synthesize an asymmetric RAM primitive.
--! This would reduce significantly the resources needed.
--!  Please check with the vendor which combination of widths is allowed for the ram primitives.
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity cc_ram_fifo is
  generic (

    --! number of words to store (in case of mixed widths, the stored width is maximum of the two)
    g_NUM_WORDS          : positive;
    --! size of input words in bits
    g_INPUT_WIDTH        : positive;
    --! size of output words in bits
    g_OUTPUT_WIDTH       : positive   := g_INPUT_WIDTH;
    --! enable first word fall through (or lookahead, or streaming)
    g_ENABLE_FWFT        : boolean    := false;
    --! size of input used words in bits
    g_INPUT_USEDW_WIDTH  : positive   := log2ceil(maximum(g_INPUT_WIDTH, g_OUTPUT_WIDTH)
                                          * g_NUM_WORDS / g_INPUT_WIDTH);
    --! size of input used words in bits
    g_OUTPUT_USEDW_WIDTH : positive   := log2ceil(maximum(g_INPUT_WIDTH, g_OUTPUT_WIDTH)
                                          * g_NUM_WORDS / g_OUTPUT_WIDTH);
    --! Implementation style
    g_IMPL_STYLE         : compiler_t := get_compiler
  );
  port (
    reset_i   : in    std_logic;                                     --! asynchronous reset
    --! @virtualbus FIFO @dir in write interface
    wrclk_i   : in    std_logic;                                     --! write clock
    data_i    : in    std_logic_vector(g_INPUT_WIDTH - 1 downto 0);  --! data_i input on write clock
    wrreq_i   : in    std_logic;                                     --! write request on write clock
    wrusedw_o : out   unsigned(g_INPUT_USEDW_WIDTH - 1 downto 0);    --! number of words used on write clock
    wrempty_o : out   std_logic;                                     --! empty signal on write clock
    wrfull_o  : out   std_logic;                                     --! full signal on write clock
    --! @end
    --! @virtualbus FIFO @dir out read interface
    rdclk_i   : in    std_logic;                                     --! read clock
    rdreq_i   : in    std_logic;                                     --! read request on read clock
    q_o       : out   std_logic_vector(g_OUTPUT_WIDTH - 1 downto 0); --! data_i output on read clock
    rdusedw_o : out   unsigned(g_OUTPUT_USEDW_WIDTH - 1 downto 0);   --! number of words used on read clock
    rdempty_o : out   std_logic;                                     --! empty signal on read clock
    rdfull_o  : out   std_logic                                      --! full signal on read clock
  --! @end
  );
end entity cc_ram_fifo;

architecture rtl of cc_ram_fifo is

  --! internal memory width and depth
  constant c_MEM_WIDTH : positive := minimum(g_INPUT_WIDTH, g_OUTPUT_WIDTH);
  constant c_MEM_DEPTH : positive := maximum(g_INPUT_WIDTH, g_OUTPUT_WIDTH) / c_MEM_WIDTH * g_NUM_WORDS;
  --! Ratio between write port and memory
  constant c_WR_RATIO  : positive := g_INPUT_WIDTH / c_MEM_WIDTH;
  --! Ratio between read port and memory
  constant c_RD_RATIO  : positive := g_OUTPUT_WIDTH / c_MEM_WIDTH;
  --! Number of words in memory as seen from the write port
  constant c_WR_WORDS  : positive := c_MEM_DEPTH / c_WR_RATIO;
  --! Number of words in memory as seen from the read port
  constant c_RD_WORDS  : positive := c_MEM_DEPTH / c_RD_RATIO;

  -- write interface signals
  signal data_in      : std_logic_vector(g_INPUT_WIDTH - 1 downto 0);
  signal wrreq        : std_logic;
  signal wrfull       : std_logic;
  -- write side pointers
  signal wr_ptr       : natural range 0 to c_WR_WORDS - 1 := 0;
  signal wrd_ptr      : natural range 0 to c_WR_WORDS - 1 := 0;
  signal wr_ptr_gray  : std_logic_vector(log2ceil(c_WR_WORDS) - 1 downto 0);
  signal wrd_ptr_gray : std_logic_vector(log2ceil(c_RD_WORDS) - 1 downto 0);
  signal int_wusedw   : natural range 0 to c_WR_WORDS     := 0;

  -- read interface signals
  signal data_out : std_logic_vector(g_OUTPUT_WIDTH - 1 downto 0);
  signal rdreq    : std_logic;
  signal rdempty  : std_logic;

  -- memory pointers
  signal rd_ptr       : natural range 0 to c_RD_WORDS - 1 := 0;
  signal rwr_ptr      : natural range 0 to c_RD_WORDS - 1 := 0;
  signal rd_ptr_gray  : std_logic_vector(log2ceil(c_RD_WORDS) - 1 downto 0);
  signal rwr_ptr_gray : std_logic_vector(log2ceil(c_WR_WORDS) - 1 downto 0);
  signal int_rusedw   : natural range 0 to c_RD_WORDS     := 0;

  -- internal request with overflow and underflow safety
  signal wr_safe,  rd_safe : std_logic;
  -- signals for FWFT generate
  signal int_empty         : std_logic;
  signal int_rdreq         : std_logic;

  -- synchronized reset signals
  signal wr_reset, rd_reset : std_logic;

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

  data_in  <= data_i;
  wrreq    <= wrreq_i;
  wrfull_o <= wrfull or wr_reset;

  ------------------------------------------------------------------------------
  -- Clock Crossing FIFO
  ------------------------------------------------------------------------------

  -- overflow and underflow safety
  wr_safe <= wrreq and not wrfull;
  rd_safe <= int_rdreq and not int_empty;

  -- clock crossing with gray pointers to avoid metastability
  -- add register after gray conversion to ensure correct cdc
  wr_ptr_gray <= bin2gray(wr_ptr, c_WR_WORDS) when rising_edge(wrclk_i);
  rd_ptr_gray <= bin2gray(rd_ptr, c_RD_WORDS) when rising_edge(rdclk_i);
  rwr_ptr     <= gray2bin(rwr_ptr_gray) * c_WR_RATIO / c_RD_RATIO;
  wrd_ptr     <= gray2bin(wrd_ptr_gray) * c_RD_RATIO / c_WR_RATIO;

  wr_ptr_synchro : entity work.synchro
    generic map (
      g_DATA_LENGTH => wr_ptr_gray'length,
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
      g_DATA_LENGTH => rd_ptr_gray'length,
      g_NUM_STAGES  => 2
    )
    port map (
      clk_i   => wrclk_i,
      reset_i => wr_reset,
      data_i  => rd_ptr_gray,
      data_o  => wrd_ptr_gray
    );

  --! keep count of used words
  int_wusedw <= c_WR_WORDS + wr_ptr - wrd_ptr when wr_ptr < wrd_ptr else
                wr_ptr - wrd_ptr;
  wrusedw_o  <= to_unsigned(int_wusedw, wrusedw_o'length);

  int_rusedw <= c_RD_WORDS + rwr_ptr - rd_ptr when rwr_ptr < rd_ptr else
                rwr_ptr - rd_ptr;
  rdusedw_o  <= to_unsigned(int_rusedw, rdusedw_o'length);

  -- drive full and empty signals
  wrfull    <= '1' when int_wusedw = c_WR_WORDS - 1 else
               '0';
  wrempty_o <= '1' when int_wusedw = 0 else
               '0';
  rdfull_o  <= '1' when int_rusedw = c_RD_WORDS - 1 else
               '0';
  int_empty <= '1' when int_rusedw = 0 else
               '0';

  --! write pointer logic
  proc_wr_ptr : process (wrclk_i) is
  begin

    if rising_edge(wrclk_i) then
      if (wr_reset = '1') then
        wr_ptr <= 0;
      else
        if (wr_safe = '1') then
          if (wr_ptr = c_WR_WORDS - 1) then
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
          if (rd_ptr = c_RD_WORDS - 1) then
            rd_ptr <= 0;
          else
            rd_ptr <= rd_ptr + 1;
          end if;
        end if;
      end if;
    end if;

  end process proc_rd_ptr;

  -- ram instance
  fifo_ram_inst : entity colibri.simple_dpram
    generic map (
      g_A_DATA_WIDTH => g_INPUT_WIDTH,
      g_B_DATA_WIDTH => g_OUTPUT_WIDTH,
      g_N_WORDS      => g_NUM_WORDS,
      g_A_ADDR_WIDTH => wr_ptr_gray'length,
      g_B_ADDR_WIDTH => rd_ptr_gray'length,
      g_IMPL_STYLE   => g_IMPL_STYLE
    )
    port map (
      wrclk_i  => wrclk_i,
      wren_i   => wr_safe and not wr_reset,
      wraddr_i => to_unsigned(wr_ptr,wr_ptr_gray'length),
      wrdata_i => data_in,
      --
      rdclk_i  => rdclk_i,
      rden_i   => rd_safe and not rd_reset,
      rdaddr_i => to_unsigned(rd_ptr,rd_ptr_gray'length),
      rddata_o => data_out
    );

  ------------------------------------------------------------------------------
  -- First Word Fall Through logic
  ------------------------------------------------------------------------------
  gen_stream_fifo : if g_ENABLE_FWFT generate
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

  q_o       <= data_out;
  rdempty_o <= rdempty;
  rdreq     <= rdreq_i;

end architecture rtl;
