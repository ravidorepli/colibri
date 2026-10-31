--! @title Run-Length Encoder
--! @file rle_encode.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 02-07-2024
--! @version 0.1

--! Some of the work was inspired by VHDL Whiz
--! Release log:
--! - 0.1 first release
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;

entity rle_encode is
  generic (
    g_WORD_WIDTH  : positive := 16;
    g_COUNT_WIDTH : positive := 3
  );
  port (
    clk_i       : in    std_logic;
    reset_i     : in    std_logic;
    --! flush signal to output words
    flush_i     : in    std_logic;
    --! @virtualbus stream @dir in sink
    snk_ready_o : out   std_logic;
    snk_valid_i : in    std_logic;
    snk_data_i  : in    std_logic_vector(g_WORD_WIDTH - 1 downto 0);
    --! @end
    --! @virtualbus stream @dir out source
    src_ready_i : in    std_logic;
    src_valid_o : out   std_logic;
    src_data_o  : out   std_logic_vector(g_WORD_WIDTH + g_COUNT_WIDTH - 1 downto 0)
  --! @end
  );
end entity rle_encode;

architecture rtl of rle_encode is

  constant c_WORD_MAX : positive := 2 ** g_COUNT_WIDTH - 1;

  type sig_t is record
    word_cnt : natural range 0 to c_WORD_MAX;
    buf      : snk_data_i'subtype;
    odata    : src_data_o'subtype;
    valid    : std_logic;
    ready    : std_logic;
    flush    : std_logic; -- flush seen flag
  end record sig_t;

  constant c_SIG_INIT : sig_t :=
  (
    word_cnt => 0,
    buf      => (others => '0'),
    odata    => (others => '0'),
    valid    => '0',
    ready    => '0',
    flush    => '0'
  );

  signal rreg, rcmb : sig_t := c_SIG_INIT;
  signal skid_data  : snk_data_i'subtype;
  signal skid_valid : std_logic;

begin

  rreg <= rcmb when rising_edge(clk_i);

  skid_buffer_inst : entity colibri.skid_buffer
    generic map (
      g_DATA_WIDTH => g_WORD_WIDTH
    )
    port map (
      clk_i       => clk_i,
      reset_i     => reset_i or flush_i,
      snk_empty_i => (others => '0'),
      snk_keep_i  => (others => '0'),
      snk_sop_i   => '0',
      snk_eop_i   => '0',
      snk_data_i  => snk_data_i,
      snk_valid_i => snk_valid_i,
      snk_ready_o => snk_ready_o,
      src_empty_o => open,
      src_keep_o  => open,
      src_sop_o   => open,
      src_eop_o   => open,
      src_data_o  => skid_data,
      src_valid_o => skid_valid,
      src_ready_i => rcmb.ready
    );

  proc_encode : process (all) is

    variable v_int : sig_t;

  begin

    v_int := rreg;

    -- acknowledge a read
    if (src_ready_i = '1' and rreg.valid = '1') then
      v_int.valid := '0';
      v_int.odata := (others => '0');
    end if;

    if (flush_i = '1' and rreg.word_cnt /= 0) then
      v_int.flush := '1'; -- set flag
    end if;

    v_int.ready := not v_int.valid and not v_int.flush;

    if (v_int.flush = '1' and v_int.valid = '0') then
      v_int.flush    := '0'; -- reset flag
      v_int.valid    := '1';
      v_int.odata    := std_logic_vector(to_unsigned(rreg.word_cnt, g_COUNT_WIDTH)) & rreg.buf;
      v_int.word_cnt := 0;
    end if;

    -- if input is valid and no word is buffered
    if (skid_valid = '1' and v_int.ready = '1') then
      v_int.buf := skid_data;
      -- if the counter was maxed
      if (rreg.word_cnt = c_WORD_MAX) then
        v_int.valid    := '1';
        v_int.odata    := std_logic_vector(to_unsigned(rreg.word_cnt, g_COUNT_WIDTH)) & rreg.buf;
        v_int.word_cnt := 1;
      else
        v_int.word_cnt := rreg.word_cnt + 1;
      end if;
      -- if it's a new buf
      if (rreg.word_cnt /= 0 and (rreg.buf /= skid_data)) then
        v_int.valid    := '1';
        v_int.odata    := std_logic_vector(to_unsigned(rreg.word_cnt, g_COUNT_WIDTH)) & rreg.buf;
        v_int.word_cnt := 1;
      end if;
    end if;

    if (reset_i) then
      v_int := c_SIG_INIT;
    end if;

    rcmb <= v_int;

  end process proc_encode;

  src_data_o  <= rreg.odata;
  src_valid_o <= rreg.valid;

end architecture rtl;
