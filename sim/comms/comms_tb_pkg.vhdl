-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library vunit_lib;
  context vunit_lib.vunit_context;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_avalon_st;
  context bitvis_vip_avalon_st.vvc_context;

library bitvis_vip_axistream;
  context bitvis_vip_axistream.vvc_context;

library colibri;
  context colibri.common;

package comms_tb_pkg is

  -- 40 MHz Clock
  constant c_CLK_FREQ   : natural := 40e6;
  constant c_CLK_PERIOD : time    := 1 sec / c_CLK_FREQ;
  constant c_CLK_GEN    : natural := 0;

  constant c_AV_ST_SRC_IDX : natural := 0;
  constant c_AV_ST_SNK_IDX : natural := 1;
  constant c_AXIS_CRC_IDX  : natural := 2;
  -- Define the default value for the BFM config
  constant c_AVST_CONFIG   : t_avalon_st_bfm_config :=
  (
    max_wait_cycles          => 100,
    max_wait_cycles_severity => ERROR,
    clock_period             => c_CLK_PERIOD,
    clock_period_margin      => 0 ns,
    clock_margin_severity    => TB_ERROR,
    setup_time               => -1 ns,
    hold_time                => -1 ns,
    bfm_sync                 => SYNC_ON_CLOCK_ONLY,
    match_strictness         => MATCH_EXACT,
    symbol_width             => 8,
    first_symbol_in_msb      => true,
    max_channel              => 0,
    use_packet_transfer      => true,
    id_for_bfm               => ID_BFM
  );
  constant c_AXISTREAM_CFG : t_axistream_bfm_config :=
  (
    max_wait_cycles                => 1000000,
    max_wait_cycles_severity       => ERROR,
    clock_period                   => -1 ns,
    clock_period_margin            => 0 ns,
    clock_margin_severity          => TB_ERROR,
    setup_time                     => -1 ns,
    hold_time                      => -1 ns,
    bfm_sync                       => SYNC_ON_CLOCK_ONLY,
    match_strictness               => MATCH_EXACT,
    byte_endianness                => LOWER_BYTE_LEFT,
    valid_low_at_word_num          => 0,
    valid_low_multiple_random_prob => 0.5,
    valid_low_duration             => 0,
    valid_low_max_random_duration  => 5,
    check_packet_length            => false,
    protocol_error_severity        => ERROR,
    ready_low_at_word_num          => 0,
    ready_low_multiple_random_prob => 0.5,
    ready_low_duration             => 0,
    ready_low_max_random_duration  => 5,
    ready_default_value            => '1',
    id_for_bfm                     => ID_BFM
  );

  --   helpers
  function fill_array (n_bytes : natural) return t_slv_array;

  function to_byte_array (vec : std_logic_vector) return t_slv_array;

  function string_to_slv (str_i : string; length: positive) return std_logic_vector;

end package comms_tb_pkg;

package body comms_tb_pkg is

  function fill_array (n_bytes : natural) return t_slv_array is

    variable v_res : t_slv_array(0 to n_bytes - 1)(7 downto 0);

  begin

    for i in 0 to n_bytes - 1 loop
      v_res(i) := std_logic_vector(to_unsigned((i mod 256), 8));
    end loop;

    return v_res;

  end function fill_array;

  function to_byte_array (vec : std_logic_vector) return t_slv_array is

    variable v_res : t_slv_array(0 to vec'length / 8 - 1)(7 downto 0);

  begin

    for i in 0 to (vec'length / 8) - 1 loop
      v_res(i) := vec(vec'left - i * 8 downto vec'length - (i + 1) * 8);
    end loop;

    return v_res;

  end function to_byte_array;

  function string_to_slv (
    str_i : string;
    length: positive
  ) return std_logic_vector is

    variable v_hex  : std_logic_vector(3 downto 0);
    variable v_vect : std_logic_vector(length - 1 downto 0);

  begin

    v_vect := (others => '0');

    for i in str_i'range loop

      case str_i(i) is

        when '0' =>
          v_hex := x"0";

        when '1' =>
          v_hex := x"1";

        when '2' =>
          v_hex := x"2";

        when '3' =>
          v_hex := x"3";

        when '4' =>
          v_hex := x"4";

        when '5' =>
          v_hex := x"5";

        when '6' =>
          v_hex := x"6";

        when '7' =>
          v_hex := x"7";

        when '8' =>
          v_hex := x"8";

        when '9' =>
          v_hex := x"9";

        when 'a' | 'A' =>
          v_hex := x"a";

        when 'b' | 'B' =>
          v_hex := x"b";

        when 'c' | 'C' =>
          v_hex := x"c";

        when 'd' | 'D' =>
          v_hex := x"d";

        when 'e' | 'E' =>
          v_hex := x"e";

        when 'f' | 'F' =>
          v_hex := x"f";

        when others =>
          report "illegal char"
            severity ERROR;

      end case;

      v_vect             := v_vect(v_vect'left - 4 downto 0) & 4x"0";
      v_vect(3 downto 0) := v_hex;

    end loop;

    return v_vect;

  end function string_to_slv;

end package body comms_tb_pkg;
