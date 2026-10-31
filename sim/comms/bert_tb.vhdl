-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;

library osvvm;
  use osvvm.randompkg.all;
  use osvvm.coveragepkg.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;

entity bert_tb is
  generic (
    RUNNER_CFG : string;
    constant g_DUT_DELAY  : positive := 10;
    constant g_DATA_WIDTH  : positive := 8
  );
end entity bert_tb;

architecture sim of bert_tb is

  shared variable v_rv        : RandomPType;
  signal          v_ber_cov   : CoverageIDType;
  signal          v_valid_cov : CoverageIDType;

  constant c_CLK_PERIOD : time    := 10 ns;
  constant c_COV_GOAL   : natural := 10;

  constant c_STATS_WIDTH : natural := 32;

  signal clk                : std_logic := '1';
  signal reset              : std_logic := '1';
  signal snk_data, src_data : std_logic_vector(g_DATA_WIDTH - 1 downto 0);
  signal snk_valid          : std_logic;
  signal src_valid          : std_logic;
  signal dut_data           : std_logic_vector(g_DATA_WIDTH - 1 downto 0);
  signal flip_mask          : std_logic_vector(g_DATA_WIDTH - 1 downto 0);
  signal dut_valid          : std_logic;

  signal bits_flipped  : unsigned(c_STATS_WIDTH - 1 downto 0);
  signal total_bits    : unsigned(c_STATS_WIDTH - 1 downto 0);
  signal word_errors   : unsigned(c_STATS_WIDTH - 1 downto 0);
  signal invalid_words : unsigned(c_STATS_WIDTH - 1 downto 0);

  type delay_t is array (natural range 0 to g_DUT_DELAY - 1) of src_data'subtype;

  signal delay_src  : delay_t := (others => (others => '0'));
  signal delay_mask : delay_t := (others => (others => '0'));

begin

  clk <= not clk after c_CLK_PERIOD / 2;

  bert_dut_inst : entity colibri.bert
    generic map (
      g_DATA_WIDTH  => g_DATA_WIDTH,
      g_STATS_WIDTH => c_STATS_WIDTH,
      g_DUT_DELAY   => g_DUT_DELAY
    )
    port map (
      clk_i   => clk,
      reset_i => reset,
      -- data from dut
      snk_data_i  => snk_data,
      snk_valid_i => snk_valid,
      -- data to dut
      src_data_o  => src_data,
      src_valid_o => src_valid,
      -- counters
      bit_errors_o    => bits_flipped,
      total_bits_o    => total_bits,
      word_errors_o   => word_errors,
      invalid_words_o => invalid_words
    );

  snk_data  <= dut_data;
  snk_valid <= dut_valid;

  dut_data <= delay_src(0) xor delay_mask(0);

  proc_delay_word : process (clk) is
  begin

    if rising_edge(clk) then
      delay_src  <= delay_src(1 to delay_src'length -1) & (src_data);
      delay_mask <= delay_mask(1 to delay_mask'length -1) & (flip_mask);
    end if;

  end process proc_delay_word;

  proc_gen_error : process is

    variable v_point     : natural;
    variable v_bit_pos   : natural;
    variable v_prev_vals : integer_vector(g_DATA_WIDTH - 1 downto 0) := (others => integer'low);

  begin

    wait until reset = '0';

    loop
      wait until rising_edge(clk);
      -- get a value to test
      v_point     := GetRandPoint(v_ber_cov);
      flip_mask   <= (others => '0');
      v_prev_vals := (others => integer'low);
      wait for 0 ns;
      -- generate flip mask

      for i in 0 to v_point - 1 loop
        v_bit_pos            := v_rv.RandInt(0, g_DATA_WIDTH - 1, v_prev_vals); -- generate random int and exclude previous bits
        flip_mask(v_bit_pos) <= '1';
        v_prev_vals          := v_prev_vals(g_DATA_WIDTH - 2 downto 0) & v_bit_pos;
      end loop;

      wait for 0 ns;
    end loop;

  end process proc_gen_error;

  proc_gen_valid : process is
  begin

    wait until reset = '0';

    loop
      wait until rising_edge(clk);
      dut_valid <= v_rv.RandSlv(1)(1);
    end loop;

  end process proc_gen_valid;

  proc_sequencer : process is

    variable v_point               : natural;
    variable v_total_bits_flipped  : natural;
    variable v_total_bits_sent     : natural;
    variable v_total_invalid_words : natural;
    variable v_total_error_words   : natural;

  begin

    ---------------- VUNIT SETUP ---------------
    test_runner_setup(runner, RUNNER_CFG);
    info("Starting OSVVM");
    v_ber_cov   <= NewID("Bit Error Rate");
    v_valid_cov <= NewID("Valid Toggle");
    wait for 0 ns;
    AddBins(v_ber_cov, c_COV_GOAL, GenBin(0, g_DATA_WIDTH)); -- cover all bytes
    AddBins(v_valid_cov, c_COV_GOAL, GenBin(0,1));           -- cover valid toggle

    -- TEST : normal behaviour
    if run("bert") then
      wait for c_CLK_PERIOD;
      reset                 <= '0';
      v_total_bits_flipped  := 0;
      v_total_bits_sent     := 0;
      v_total_invalid_words := 0;
      v_total_error_words   := 0;
      -- propagation delay
      for i in 0 to g_DUT_DELAY loop
        wait until rising_edge(clk);

      end loop;

      loop
        wait until rising_edge(clk);
        v_total_bits_sent := v_total_bits_sent + g_DATA_WIDTH;
        if (dut_valid) then
          v_point              := count_ones(delay_mask(0));
          v_total_bits_flipped := v_total_bits_flipped + v_point;
          if (v_point /= 0) then
            v_total_error_words := v_total_error_words + 1;
          end if;
        else
          v_total_invalid_words := v_total_invalid_words + 1;
        end if;
        info("Bits flipped: " &to_string(v_point));
        ICover(v_valid_cov, to_integer((dut_valid = '1')));
        ICover(v_ber_cov, v_point);
        exit when IsCovered(v_ber_cov) and IsCovered(v_valid_cov);
      end loop;

    end if;

    wait for 2 * c_CLK_PERIOD;
    WriteBin(v_ber_cov);
    WriteBin(v_valid_cov);
    info("------------------------------------------------");
    info("TOTAL bits flipped: " & to_string(v_total_bits_flipped));
    info("TOTAL bits transmitted: " & to_string(v_total_bits_sent));
    info("TOTAL words corrupted: " & to_string(v_total_error_words));
    info("TOTAL invalid words: " & to_string(v_total_invalid_words));
    check(to_integer(bits_flipped) = v_total_bits_flipped, "bit flip counter mismatch! exp "& to_string(v_total_bits_flipped) &" dut "&to_string(to_integer(bits_flipped)));
    check(to_integer(total_bits) = v_total_bits_sent, "total counter mismatch! exp "& to_string(v_total_bits_sent) &" dut "&to_string(to_integer(total_bits)));
    check(to_integer(word_errors) = v_total_error_words, "Corrupted words mismatch! exp "& to_string(v_total_error_words) &" dut "&to_string(to_integer(word_errors)));
    check(to_integer(invalid_words) = v_total_invalid_words, "Invalid words mismatch! exp "& to_string(v_total_invalid_words) &" dut "&to_string(to_integer(invalid_words)));
    -- VUnit cleanup
    test_runner_cleanup(runner);

  end process proc_sequencer;

end architecture sim;
