--! @title Bit Error Rate Tester
--! @file bert.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 25-03-2025
--! @version 0.1
--! This entity implements a simple Bit Error Rate Tester.
--! A PRBS generator with configurable polynomials is used to generate a stream of data towards the DUT.
--! The DUT should be connected in a loopback, propagation time can be configured with the g_DUT_DELAY parameter.
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.poly.all;

entity bert is
  generic (
    g_DATA_WIDTH  : positive         := 32; --! word size
    g_STATS_WIDTH : positive         := 64; --! statistics counters size
    g_PRBS_POLY   : std_logic_vector := c_PRBS_7;
    g_DUT_DELAY   : positive         := 1
  );
  port (
    clk_i           : in    std_logic;
    reset_i         : in    std_logic;
    --! @virtualbus Avalon-ST @dir in sink
    snk_data_i      : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0); --! data input
    snk_valid_i     : in    std_logic;                                   --! input valid signal
    --! @end
    --! @virtualbus Avalon-ST @dir out source
    src_data_o      : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0); --! data output
    src_valid_o     : out   std_logic;                                   --! valid output signal
    --! @end
    bit_errors_o    : out   unsigned(g_STATS_WIDTH - 1 downto 0);        --! number of bits flipped
    total_bits_o    : out   unsigned(g_STATS_WIDTH - 1 downto 0);        --! total bits transmitted
    word_errors_o   : out   unsigned(g_STATS_WIDTH - 1 downto 0);        --! number of corrupted words
    invalid_words_o : out   unsigned(g_STATS_WIDTH - 1 downto 0)         --! total invalid words (i.e. snk_valid = 0)
  );
end entity bert;

architecture rtl of bert is

  constant c_PRBS_SIGNATURE : snk_data_i'subtype := gen_even(g_DATA_WIDTH);

  type fsm_t is (S_RESET, S_START, S_COUNT);

  type sig_t is record
    state          : fsm_t;
    delay          : natural range 0 to g_DUT_DELAY + 1;
    valid          : std_logic;
    bit_flip       : natural range 0 to g_DATA_WIDTH;
    invalid_words  :  unsigned(g_STATS_WIDTH - 1 downto 0);
    word_errors    :  unsigned(g_STATS_WIDTH - 1 downto 0);
    total_bit_flip :  unsigned(g_STATS_WIDTH - 1 downto 0);
    total_bits     :  unsigned(g_STATS_WIDTH - 1 downto 0);
  end record sig_t;

  constant c_FSM_INIT : sig_t :=
  (
    state          => S_RESET,
    delay          => 0,
    valid          => '0',
    bit_flip       => 0,
    invalid_words  => (others => '0'),
    word_errors    => (others => '0'),
    total_bit_flip => (others => '0'),
    total_bits     => (others => '0')
  );
  signal   rreg       : sig_t;
  signal   rcmb       : sig_t;

  type delay_t is array (natural range 0 to g_DUT_DELAY - 1) of src_data_o'subtype;

  signal delay_buf : delay_t;

begin

  --! PRBS generator
  scrambler_inst : entity colibri.scrambler(rtl)
    generic map (
      g_DATA_WIDTH     => g_DATA_WIDTH,
      g_SCRAMBLER_POLY => g_PRBS_POLY
    )
    port map (
      clk_i       => clk_i,
      reset_i     => reset_i,
      snk_data_i  => c_PRBS_SIGNATURE,
      snk_valid_i => '1',
      snk_ready_o => open,
      src_data_o  => src_data_o,
      src_valid_o => src_valid_o,
      src_ready_i => '1'
    );

  --! internal delay to absorb DUT latency
  proc_delay_word : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      delay_buf <= delay_buf(1 to delay_buf'length - 1) & src_data_o;
    end if;

  end process proc_delay_word;

  --! FSM clocked
  rreg <= rcmb when rising_edge(clk_i);
  --! main FSM process
  proc_fsm_cmb : process (all) is

    variable v_int : sig_t;

  begin

    v_int := rreg;

    case rreg.state is

      when S_RESET =>
        v_int.state := S_START;

      when S_START =>
        v_int.bit_flip := count_ones(snk_data_i xor delay_buf(0));
        v_int.delay    := rreg.delay + 1;
        v_int.valid    := snk_valid_i;

        if (rreg.delay = g_DUT_DELAY) then
          v_int.state := S_COUNT;
          v_int.delay := 0;
        end if;

      when S_COUNT =>
        v_int.bit_flip := count_ones(snk_data_i xor delay_buf(0));
        v_int.valid    := snk_valid_i;

        -- STATISTICS COUNTERS
        -- sum the old value to guarantee timing closure
        v_int.total_bits := rreg.total_bits + g_DATA_WIDTH;

        if (rreg.valid = '1') then
          v_int.total_bit_flip := rreg.total_bit_flip + rreg.bit_flip;
          if (rreg.bit_flip /= 0) then
            v_int.word_errors := rreg.word_errors + 1;
          end if;
        else
          v_int.invalid_words := rreg.invalid_words + 1;
        end if;

    end case;

    if (reset_i) then
      v_int := c_FSM_INIT;
    end if;

    rcmb <= v_int;

  end process proc_fsm_cmb;

  total_bits_o    <= rreg.total_bits;
  bit_errors_o    <= rreg.total_bit_flip;
  word_errors_o   <= rreg.word_errors;
  invalid_words_o <= rreg.invalid_words;

end architecture rtl;
