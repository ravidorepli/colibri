-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  context colibri.common;

library vunit_lib;
  context vunit_lib.vunit_context;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library bitvis_vip_scoreboard;

----------------------------------------------------------------------------------------------------

entity avst_ram_write_unaligned_tb is
  generic (
    RUNNER_CFG   : string;
    g_BYTE_WIDTH : positive := 8;
    g_WORD_BYTES : positive := 8;
    g_RAM_DEPTH  : positive := 100 --! RAM depth in terms of words
  );
end entity avst_ram_write_unaligned_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of avst_ram_write_unaligned_tb is

  -- Clock period
  constant c_CLK_PERIOD : time := 10 ns;

  constant c_DATA_WIDTH : positive := g_WORD_BYTES * g_BYTE_WIDTH;

  constant c_RAM_BYTES : positive := g_WORD_BYTES * g_RAM_DEPTH;

  -- UUT interface signals
  signal clk   : std_logic;
  signal reset : std_logic := '1';

  signal snk_data  : std_logic_vector(c_DATA_WIDTH - 1 downto 0)   := (others => '0');
  signal snk_empty : unsigned(log2ceil(g_WORD_BYTES) - 1 downto 0) := (others => '0');
  signal snk_sop   : std_logic                                     := '0';
  signal snk_eop   : std_logic                                     := '0';
  signal snk_valid : std_logic                                     := '0';
  signal snk_ready : std_logic;

  signal start_addr : unsigned(log2ceil(c_RAM_BYTES) - 1 downto 0) := (others => '0');
  signal flush      : std_logic                                    := '0';

  signal wr_be   : std_logic_vector(g_WORD_BYTES - 1 downto 0);
  signal wr_addr : unsigned(log2ceil(g_RAM_DEPTH) - 1 downto 0);
  signal wr_data : std_logic_vector(c_DATA_WIDTH - 1 downto 0);

  --! Data scoreboard
  package data_sb_pkg is new bitvis_vip_scoreboard.generic_sb_pkg
    generic map (
      T_ELEMENT         => snk_data'subtype,
      ELEMENT_MATCH     => std_match,
      TO_STRING_ELEMENT => to_hstring
    );

  shared variable v_data_sb : data_sb_pkg.t_generic_sb;

  --! Address scoreboard
  package addr_sb_pkg is new bitvis_vip_scoreboard.generic_sb_pkg
    generic map (
      T_ELEMENT         => start_addr'subtype,
      ELEMENT_MATCH     => std_match,
      TO_STRING_ELEMENT => to_hstring
    );

  shared variable v_addr_sb : addr_sb_pkg.t_generic_sb;

  --! Empty scoreboard
  package empty_sb_pkg is new bitvis_vip_scoreboard.generic_sb_pkg
    generic map (
      T_ELEMENT         => snk_empty'subtype,
      ELEMENT_MATCH     => std_match,
      TO_STRING_ELEMENT => to_hstring
    );

  shared variable v_empty_sb : empty_sb_pkg.t_generic_sb;

begin ----------------------------------------------------------------------------------------------

  clock_generator(clk, c_CLK_PERIOD);

  --------------------------------------------------------------------------------------------------
  --! Unit Under Test
  --------------------------------------------------------------------------------------------------
  uut_avst_ram_write_unaligned : entity colibri.avst_ram_write_unaligned
    generic map (
      g_BYTE_WIDTH => g_BYTE_WIDTH,
      g_WORD_BYTES => g_WORD_BYTES,
      g_RAM_DEPTH  => g_RAM_DEPTH
    )
    port map (
      clk_i   => clk,
      reset_i => reset,

      snk_data_i  => snk_data,
      snk_empty_i => snk_empty,
      snk_sop_i   => snk_sop,
      snk_eop_i   => snk_eop,
      snk_valid_i => snk_valid,
      snk_ready_o => snk_ready,

      start_addr_i => start_addr,
      flush_i      => flush,

      wr_be_o   => wr_be,
      wr_addr_o => wr_addr,
      wr_data_o => wr_data
    );

  --------------------------------------------------------------------------------------------------
  --! Input process
  --------------------------------------------------------------------------------------------------
  proc_input : process is

    variable v_skew : natural;

    --! Generate new random data input
    procedure progress_data is
    begin

      snk_data <= random(c_DATA_WIDTH);
      wait_num_rising_edge(clk, 1);
      v_data_sb.add_expected(snk_data);

    end procedure progress_data; -----------------------------------------------

  begin

    wait until reset = '0';
    wait_num_rising_edge(clk, 3);

    ------------------------------------------------------------------
    -- TEST 1: Start of Packet
    ------------------------------------------------------------------

    start_addr <= to_unsigned(random(0, g_RAM_DEPTH) * g_WORD_BYTES + random(1, g_WORD_BYTES - 1),
                              start_addr'length);
    snk_valid  <= '1';
    snk_sop    <= '1';
    progress_data;
    snk_sop    <= '0';

    v_addr_sb.add_expected(start_addr);

    ------------------------------------------------------------------
    -- TEST 2: Packet body
    ------------------------------------------------------------------

    for i in 1 to 3 loop
      progress_data;
    end loop;

    ------------------------------------------------------------------
    -- TEST 3: Input PAUSE (`valid` drops)
    ------------------------------------------------------------------

    -- PAUSE the input
    snk_valid <= '0';
    wait_num_rising_edge(clk, 1);

    ------------------------------------------------------------------
    -- TEST 4: End of Packet
    ------------------------------------------------------------------

    snk_valid <= '1';
    snk_eop   <= '1';
    snk_empty <= to_unsigned(random(0, v_skew - 1), snk_empty'length);
    progress_data;
    -- Additional (zero) data is added to the queue as padding to the patrially empty EoP
    v_data_sb.add_expected(std_logic_vector(to_unsigned(0, snk_data'length)));
    v_empty_sb.add_expected(snk_empty);
    snk_eop   <= '0';
    snk_empty <= (others => '0');

    ------------------------------------------------------------------
    -- TEST 5: immediate SoP + immediate EoP
    ------------------------------------------------------------------

    -- immediate SoP (new start address with `v_skew := 1`)
    start_addr <= to_unsigned(random(0, g_RAM_DEPTH) * g_WORD_BYTES + 1, start_addr'length);
    snk_sop    <= '1';
    progress_data;
    v_addr_sb.add_expected(start_addr);
    wait until snk_ready = '1' and rising_edge(clk);
    snk_sop    <= '0';

    -- immediate EoP (2-beat packet)
    snk_eop   <= '1';
    snk_empty <= to_unsigned(g_WORD_BYTES - 1, snk_empty'length);
    progress_data;
    snk_valid <= '0';
    snk_eop   <= '0';
    snk_empty <= (others => '0');

    ------------------------------------------------------------------
    -- TEST 6: RAM writing stops after the EoP
    ------------------------------------------------------------------
    wait_num_rising_edge(clk, 5);

    ------------------------------------------------------------------
    -- TEST 7: Singe-beat packets (simultaneous SoP and EoP)
    ------------------------------------------------------------------

    snk_sop   <= '1';
    snk_eop   <= '1';
    snk_valid <= '1';

    for i in 1 to g_WORD_BYTES loop

      start_addr <= to_unsigned(random(0, g_RAM_DEPTH) * g_WORD_BYTES + (i mod g_WORD_BYTES), start_addr'length);
      snk_empty  <= to_unsigned(g_WORD_BYTES - i, snk_empty'length);
      progress_data;
      v_addr_sb.add_expected(start_addr);

      if (2 * i > g_WORD_BYTES and i < g_WORD_BYTES) then
        v_data_sb.add_expected(std_logic_vector(to_unsigned(0, snk_data'length)));
        wait for c_CLK_PERIOD / 10;
        check_value(snk_ready, '0', "TEST 7, it." & to_string(i) & ": Ready should be de-asserted after an EoP");
        wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
        check_value(snk_ready, '1', "TEST 7, it." & to_string(i) & ": Ready should be re-asserted after an EoP");
      end if;

    end loop;

    snk_sop   <= '0';
    snk_eop   <= '0';
    snk_valid <= '0';
    snk_empty <= (others => '0');

    ------------------------------------------------------------------
    -- TEST 8: Aligned RAM writing
    ------------------------------------------------------------------
    wait_num_rising_edge(clk, 5);

    for packet in 1 to 2 loop
      start_addr <= to_unsigned(random(0, g_RAM_DEPTH) * g_WORD_BYTES, start_addr'length);
      snk_sop    <= '1';
      snk_valid  <= '1';
      progress_data;
      v_addr_sb.add_expected(start_addr);
      snk_sop    <= '0';

      for i in 1 to 3 * g_RAM_DEPTH loop
        progress_data;

        -- Test that random SoP and start addr. variation is ignored
        start_addr <= unsigned(random(start_addr'length));
        snk_sop    <= random(VOID);
      end loop;

      snk_eop   <= '1';
      progress_data;
      snk_eop   <= '0';
      snk_sop   <= '0';
      snk_valid <= '0';
    end loop;

    ------------------------------------------------------------------
    -- TEST 9: Flush before EoP (2 packets terminated by `flush_i`)
    ------------------------------------------------------------------
    wait_num_rising_edge(clk, 5);

    for packet in 1 to 2 loop
      start_addr <= to_unsigned(random(0, g_RAM_DEPTH) * g_WORD_BYTES + random(1, g_WORD_BYTES - 1),
                                start_addr'length);
      snk_sop    <= '1';
      snk_valid  <= '1';
      progress_data;
      v_addr_sb.add_expected(start_addr);
      snk_sop    <= '0';

      for i in 1 to 3 loop
        progress_data;
      end loop;

      v_data_sb.add_expected(std_logic_vector(to_unsigned(0, snk_data'length)));
      snk_valid <= '0';
      flush     <= '1';
      wait_num_rising_edge(clk, 1);
      flush     <= '0';
    end loop;

    wait;

  end process proc_input; --------------------------------------------------------------------------

  --------------------------------------------------------------------------------------------------
  --! VUnit verification process
  --------------------------------------------------------------------------------------------------
  proc_verify : process is

    variable v_addr  : wr_addr'subtype;
    variable v_skew  : natural;
    variable v_mask  : wr_be'subtype;
    variable v_empty : snk_empty'subtype;

    --! Check the output write data based on the previous and current input words
    procedure check_data (
      msg : in string
    ) is

      -- Expected bytes on the RAM write interface
      variable v_expected : slv_array_t(0 to g_WORD_BYTES - 1)(g_BYTE_WIDTH - 1 downto 0);

      -- Two previous input words are extracted from the scoreboard queue
      -- in the form of byte-arrays for better readability
      constant c_PREV_BYTES : v_expected'subtype :=
        slv_to_slv_array(v_data_sb.fetch_expected(VOID), g_BYTE_WIDTH);
      constant c_NEXT_BYTES : v_expected'subtype :=
        slv_to_slv_array(v_data_sb.peek_expected(VOID), g_BYTE_WIDTH);

    begin

      for i in 0 to v_skew - 1 loop
        v_expected(i) := c_PREV_BYTES(c_PREV_BYTES'length - v_skew + i);
      end loop;

      for i in v_skew to g_WORD_BYTES - 1 loop
        v_expected(i) := c_NEXT_BYTES(i - v_skew);
      end loop;

      check_value(wr_data, slv_array_to_slv(v_expected, g_BYTE_WIDTH), msg);

    end procedure check_data; --------------------------------------------------

    --! Check the RAM write interface
    procedure check_ram_write (
      test_id : in string
    ) is
    begin

      check_value(wr_be, v_mask, test_id & ": Incorrect write byte-enable mask");
      check_value(wr_addr, v_addr, test_id & ": Incorrect write address");
      check_data(test_id & ": Incorrect write data");

    end procedure check_ram_write; ---------------------------------------------

  begin --------------------------------------------------------------------------------------------

    -------------------------- VUNIT SETUP --------------------------
    test_runner_setup(runner, RUNNER_CFG);
    v_empty_sb.enable(VOID);
    v_addr_sb.enable(VOID);
    v_data_sb.enable(VOID);
    v_data_sb.add_expected(std_logic_vector(to_unsigned(0, snk_data'length)));

    -- Initial reset
    wait_num_rising_edge(clk, 3);
    reset <= '0';

    ------------------------------------------------------------------
    -- TEST 0: Initial state
    ------------------------------------------------------------------
    check_value(snk_ready, '0', "TEST 0: Ready should be down during the reset");
    check_stable(snk_ready, 3 * c_CLK_PERIOD, "TEST 0: Ready should be down during the reset");
    wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
    check_value(snk_ready, '1', "TEST 0: Input should immediately be ready");
    check_value(or wr_be, '0', "TEST 0: Writing should not be active without valid data");

    ------------------------------------------------------------------
    -- TEST 1: Start of Packet
    ------------------------------------------------------------------

    wait until snk_valid = '1'; -- Expecting 2CC delay between AVST input and RAM wr. output
    wait_num_rising_edge_plus_margin(clk, 2, c_CLK_PERIOD / 10);

    -- Set the expectations: word address, byte address skew, write enable mask
    v_addr := to_unsigned(to_integer(v_addr_sb.peek_expected(VOID)) / g_WORD_BYTES, v_addr'length);
    v_skew := to_integer(v_addr_sb.fetch_expected(VOID)) mod g_WORD_BYTES;

    for i in v_mask'range loop

      v_mask(v_mask'left - i) := bool_to_sl(i >= v_skew);

    end loop;

    check_ram_write("TEST 1"); -- Check the wr. interface based on the set expectations

    ------------------------------------------------------------------
    -- TEST 2: Packet body
    ------------------------------------------------------------------
    v_mask := (others => '1'); -- Full words are written during the packet body

    for i in 1 to 3 loop
      v_addr := v_addr + 1;
      wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
      check_ram_write("TEST 2, it." & to_string(i));
    end loop;

    ------------------------------------------------------------------
    -- TEST 3: Input PAUSE (`valid` drops)
    ------------------------------------------------------------------
    wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
    check_value(or wr_be, '0', "TEST 3: Writing should not be active without valid data");

    ------------------------------------------------------------------
    -- TEST 4: End of Packet
    ------------------------------------------------------------------

    wait for c_CLK_PERIOD / 10;
    check_value(snk_ready, '0', "TEST 4: Ready should be deasserted after an EoP");
    -- Ready falls for 1CC to allow for additional write which is required due to address skew
    -- (EoP beat can take 2CC to be written)
    wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
    check_value(snk_ready, '1', "TEST 4: Ready should only fall for 1CC.");

    -- A: One full word write
    v_addr := v_addr + 1;
    check_ram_write("TEST 4a");

    -- B: Residual bytes at the end of the packet
    wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);

    v_empty := v_empty_sb.fetch_expected(VOID);

    for i in v_mask'range loop

      v_mask(v_mask'left - i) := bool_to_sl(i < v_skew - v_empty);

    end loop;

    v_addr := v_addr + 1;
    check_ram_write("TEST 4b");

    ------------------------------------------------------------------
    -- TEST 5: immediate SoP + immediate EoP
    ------------------------------------------------------------------

    -- A: The SoP (address skew set to 1 byte)
    v_skew := 1;
    v_addr := to_unsigned(to_integer(v_addr_sb.fetch_expected(VOID)) / g_WORD_BYTES, v_addr'length);

    for i in v_mask'range loop

      v_mask(v_mask'left - i) := bool_to_sl(i >= v_skew);

    end loop;

    -- Writing of the new packet continues immediately (still with 2CC delay to input)
    wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
    check_ram_write("TEST 5a");

    -- B: The EoP (empty set to max. => no residual data to write)
    v_empty := to_unsigned(g_WORD_BYTES - 1, v_empty'length);
    check_value(snk_ready, '1', "TEST 5: Ready should stay asserted (short EoP)");

    for i in v_mask'range loop

      v_mask(v_mask'left - i) := bool_to_sl(i < v_skew + g_WORD_BYTES - to_integer(v_empty));

    end loop;

    v_addr := v_addr + 1;
    wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
    check_ram_write("TEST 5b");

    ------------------------------------------------------------------
    -- TEST 6: RAM writing stops after the EoP
    ------------------------------------------------------------------
    wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
    check_value(or wr_be, '0', "TEST 6: Writing should stop after the EoP");
    -- Components stays inactive without any valid input
    wait_num_rising_edge(clk, 5);
    check_stable(wr_be, 5 * c_CLK_PERIOD, "TEST 6: Writing not start spontaneously");

    ------------------------------------------------------------------
    -- TEST 7: Singe-beat packets (simultaneous SoP and EoP)
    ------------------------------------------------------------------

    -- The loop covers all possible byte occupancies (except full word, which comes later)
    for i in 1 to g_WORD_BYTES - 1 loop
      v_addr := to_unsigned(to_integer(v_addr_sb.fetch_expected(VOID)) / g_WORD_BYTES, v_addr'length);
      v_skew := i; -- Addr. skew is set to the same as packet size

      if (2 * i > g_WORD_BYTES) then -- In this case 2 writes will be required (size + skew = 2 * i)
        wait for c_CLK_PERIOD / 10;

        for b in v_mask'range loop
          v_mask(v_mask'left - b) := bool_to_sl(b >= i);
        end loop;

        check_ram_write("TEST 7, it." & to_string(i) & "a");

        for b in v_mask'range loop
          v_mask(v_mask'left - b) := bool_to_sl(b < 2 * i - g_WORD_BYTES);
        end loop;

        v_addr := v_addr + 1;
        wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
        check_ram_write("TEST 7, it." & to_string(i) & "b");
      else -- Single-write packets

        for b in v_mask'range loop
          v_mask(v_mask'left - b) := bool_to_sl(b >= i and b < 2 * i);
        end loop;

        wait for c_CLK_PERIOD / 10;
        check_ram_write("TEST 7, it." & to_string(i));
      end if;

      wait_num_rising_edge(clk, 1);

    end loop;

    -- Final single-beat example is a packet with `size = g_WORD_BYTES` and `skew = 0` (full word)
    v_mask := (others => '1');
    v_skew := 0;
    v_addr := to_unsigned(to_integer(v_addr_sb.fetch_expected(VOID)) / g_WORD_BYTES, v_addr'length);

    wait for c_CLK_PERIOD / 10;
    check_ram_write("TEST 7, it." & to_string(g_WORD_BYTES));

    ------------------------------------------------------------------
    -- TEST 8: Aligned RAM writing
    ------------------------------------------------------------------
    wait until snk_valid;
    wait_num_rising_edge(clk, 1);

    -- Two packets are generated one immediately after the other
    -- They have word-aligned address and size.
    -- SOP varies randomly to confirm it only has effect at the actual start of packet
    for packet in 1 to 2 loop
      v_addr := to_unsigned(to_integer(v_addr_sb.fetch_expected(VOID)) / g_WORD_BYTES, v_addr'length);

      for i in 0 to 3 * g_RAM_DEPTH loop
        wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
        check_ram_write("TEST 8, it." & to_string(i));
        v_addr := v_addr + 1;
      end loop;

      wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
      check_ram_write("TEST 8, EoP");
    end loop;

    ------------------------------------------------------------------
    -- TEST 9: Flush before EoP (2 packets terminated by `flush_i`)
    ------------------------------------------------------------------
    wait until snk_valid;
    wait_num_rising_edge(clk, 1);

    for packet in 1 to 2 loop
      v_addr := to_unsigned(to_integer(v_addr_sb.peek_expected(VOID)) / g_WORD_BYTES, v_addr'length);
      v_skew := to_integer(v_addr_sb.fetch_expected(VOID)) mod g_WORD_BYTES;

      for i in v_mask'range loop

        v_mask(v_mask'left - i) := bool_to_sl(i >= v_skew);

      end loop;

      for i in 0 to 3 loop
        wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
        check_ram_write("TEST 9, it." & to_string(i));
        v_addr := v_addr + 1;
        v_mask := (others => '1');
      end loop;

      for i in v_mask'range loop

        v_mask(v_mask'left - i) := bool_to_sl(i < v_skew);

      end loop;

      wait_num_rising_edge_plus_margin(clk, 1, c_CLK_PERIOD / 10);
      check_ram_write("TEST 9, Flush");
    end loop;

    wait_num_rising_edge(clk, 1);
    ------------------------- VUNIT CLEANUP --------------------------
    test_runner_cleanup(runner);

  end process proc_verify;

  test_runner_watchdog(runner, 10 ms);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
