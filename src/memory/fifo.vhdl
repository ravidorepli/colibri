--! @title Single Clock FIFO
--! @file fifo.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 14-11-2023
--! @date 13-05-2024
--! @version 0.2

--! @details
--! 0.2 add first word fall through (lookahead, streaming)
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

entity fifo is
  generic (

    --! number of words to store
    g_NUM_WORDS    : positive := 4;
    --! size of input words in bits
    g_INPUT_WIDTH  : positive := 8;
    --! size of output words in bits
    g_OUTPUT_WIDTH : positive := g_INPUT_WIDTH;
    --! enable first word fall through (or lookahead, or streaming)
    g_ENABLE_FWFT  : boolean  := false
  );
  port (
    clk_i   : in    std_logic;                                     --! common clock
    reset_i : in    std_logic;                                     --! reset_i
    data_i  : in    std_logic_vector(g_INPUT_WIDTH - 1 downto 0);  --! data_i input
    wrreq_i : in    std_logic;                                     --! write request
    rdreq_i : in    std_logic;                                     --! read request
    q_o     : out   std_logic_vector(g_OUTPUT_WIDTH - 1 downto 0); --! datao output
    usedw_o : out   unsigned(log2ceil(g_NUM_WORDS) downto 0);      --! used words
    empty_o : out   std_logic;                                     --! empty_o signal
    full_o  : out   std_logic                                      --! full_o signal
  );
end entity fifo;

architecture rtl of fifo is

  -- Width in bits of the words stored in the FIFO
  constant c_FIFO_WIDTH : positive := maximum(g_INPUT_WIDTH, g_OUTPUT_WIDTH);

  -- fifo memory storage

  type mem_t is array (0 to g_NUM_WORDS - 1) of std_logic_vector(c_FIFO_WIDTH - 1 downto 0);

  shared variable v_memory : mem_t;

  -- write interface signals
  signal data_in : std_logic_vector(c_FIFO_WIDTH - 1 downto 0);
  signal wrreq   : std_logic;
  signal full    : std_logic;

  -- read interface signals
  signal data_out : std_logic_vector(c_FIFO_WIDTH - 1 downto 0);
  signal rdreq    : std_logic;
  signal empty    : std_logic;

  -- memory pointers
  signal wr_ptr,  rd_ptr : natural range 0 to g_NUM_WORDS - 1 := 0;
  signal int_usedw       : natural range 0 to g_NUM_WORDS     := 0;

  -- internal request with overflow and underflow safety
  signal wr_safe, rd_safe : std_logic;

  -- internal signals (used in generate)
  signal int_rdreq : std_logic;
  signal int_empty : std_logic;

begin

  ------------------------------------------------------------------------------
  -- Input width conversion
  ------------------------------------------------------------------------------
  gen_up_conversion : if g_INPUT_WIDTH < g_OUTPUT_WIDTH generate
    signal gbx_ready : std_logic;
  begin

    gearbox_inst : entity colibri.gearbox
      generic map (
        g_INPUT_WIDTH  => g_INPUT_WIDTH,
        g_OUTPUT_WIDTH => g_OUTPUT_WIDTH
      )
      port map (
        clk_i       => clk_i,
        reset_i     => reset_i,
        snk_data_i  => data_i,
        snk_valid_i => wrreq_i,
        snk_ready_o => gbx_ready,
        src_data_o  => data_in,
        src_valid_o => wrreq,
        src_ready_i => not full
      );

    full_o <= not gbx_ready;

  else generate
    data_in <= data_i;
    wrreq   <= wrreq_i;
    full_o  <= full;

  end generate gen_up_conversion;

  ------------------------------------------------------------------------------
  -- FIFO logic
  ------------------------------------------------------------------------------

  -- overflow safety
  wr_safe <= wrreq and not full;

  --! keep count of used words
  proc_used_words : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        int_usedw <= 0;
      else
        if (wr_safe = '1' and rd_safe = '0') then
          int_usedw <= int_usedw + 1;
        elsif (wr_safe = '0' and rd_safe = '1') then
          int_usedw <= int_usedw - 1;
        end if;
      end if;
    end if;

  end process proc_used_words;

  usedw_o <= to_unsigned(int_usedw, usedw_o'length);

  -- drive full and empty signals
  full      <= '1' when int_usedw = g_NUM_WORDS else
               '0';
  int_empty <= '1' when int_usedw = 0 else
               '0';

  --! write pointer logic
  proc_write_ptr : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
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

  end process proc_write_ptr;

  --! read pointer logic
  proc_read_ptr : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
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

  end process proc_read_ptr;

  --! read from and write to the FIFO memory
  proc_memory : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if ((not reset_i) and wr_safe) then
        v_memory(wr_ptr) := data_in;
      end if;
    end if;

    if rising_edge(clk_i) then
      if ((not reset_i) and rd_safe) then
        data_out <= v_memory(rd_ptr);
      end if;
    end if;

  end process proc_memory;

  ------------------------------------------------------------------------------
  -- First Word Fall Through logic (enabled also in case of output width conversion)
  ------------------------------------------------------------------------------
  gen_stream_fifo : if g_ENABLE_FWFT or g_INPUT_WIDTH > g_OUTPUT_WIDTH generate
    signal reg_valid : std_logic;
    signal cmb_valid : std_logic;
  begin
    -- convert fifo to streaming mode
    proc_fifo_stream_cmb : process (all) is

      variable v_valid : std_logic; -- output register valid

    begin

      v_valid := reg_valid;

      if (rdreq = '1' and reg_valid = '1') then
        v_valid := '0';
      end if;

      if ((int_empty = '0' or wrreq = '1') and v_valid = '0') then
        int_rdreq <= '1';
        v_valid   := '1';
      else
        int_rdreq <= '0';
      end if;

      if (reset_i) then
        v_valid := '0';
      end if;

      cmb_valid <= v_valid;

    end process proc_fifo_stream_cmb;

    reg_valid <= cmb_valid when rising_edge(clk_i);
    empty     <= not reg_valid;
    rd_safe   <= int_rdreq;

  else generate
    int_rdreq <= rdreq;
    empty     <= int_empty;
    rd_safe   <= int_rdreq and (not int_empty);

  end generate gen_stream_fifo;

  ------------------------------------------------------------------------------
  -- Output width conversion
  ------------------------------------------------------------------------------
  gen_down_conversion : if g_INPUT_WIDTH > g_OUTPUT_WIDTH generate
    signal gbx_valid    : std_logic;
    signal gbx_data_out : std_logic_vector(q_o'range);
  begin

    gearbox_inst : entity colibri.gearbox
      generic map (
        g_INPUT_WIDTH  => g_INPUT_WIDTH,
        g_OUTPUT_WIDTH => g_OUTPUT_WIDTH
      )
      port map (
        clk_i       => clk_i,
        reset_i     => reset_i,
        snk_data_i  => data_out,
        snk_valid_i => not empty,
        snk_ready_o => rdreq,
        src_data_o  => gbx_data_out,
        src_valid_o => gbx_valid,
        src_ready_i => rdreq_i
      );

    empty_o <= not gbx_valid;

    -- Generate additional output delay in case First Word Fall Through is disabled
    gen_output_delay : if g_ENABLE_FWFT generate
      q_o <= gbx_data_out;
    else generate
      q_o <= gbx_data_out when rising_edge(clk_i);
    end generate gen_output_delay;

  else generate
    q_o     <= data_out;
    empty_o <= empty;
    rdreq   <= rdreq_i;

  end generate gen_down_conversion;

end architecture rtl;
