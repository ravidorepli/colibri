
--! @title Binary File I/O
--! @file binaryio.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 21-03-2025
--! @version 0.3

--! Release log:
--! - 0.3 (mvodnik) added incomplete read functionality
--! - 0.2 fixed write issue and variable in procedure
--! - 0.1 first release

--! Work inspired by VHDL-extras (http://github.com/kevinpt/vhdl-extras)
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;

----------------------------------------------------------------------------------------------------

package binaryio is

  alias byte is character;

  type binary_file_t is file of byte;

  ------------------------------------------------------------------------------
  --! read from binary file -> std_logic_vector
  ------------------------------------------------------------------------------

  procedure read (
    file bin_file : binary_file_t;
    word          : out std_logic_vector
  );

  --! incomplete read allowed (returns number of empty bytes at LSB)

  procedure read (
    file bin_file : binary_file_t;
    word          : out std_logic_vector;
    empty         : out natural
  );

  ------------------------------------------------------------------------------
  --! write to binary file <- unsigned
  ------------------------------------------------------------------------------

  procedure write (
    file bin_file : binary_file_t;
    word          : std_logic_vector
  );

  ------------------------------------------------------------------------------
  --! read from binary file -> unsigned
  ------------------------------------------------------------------------------

  procedure read (
    file bin_file : binary_file_t;
    word          : out unsigned
  );

  --! incomplete read allowed (returns number of empty bytes at LSB)

  procedure read (
    file bin_file : binary_file_t;
    word          : out unsigned;
    empty         : out natural
  );

  ------------------------------------------------------------------------------
  --! write to binary file <- unsigned
  ------------------------------------------------------------------------------

  procedure write (
    file bin_file : binary_file_t;
    word          : unsigned
  );

end package binaryio;

----------------------------------------------------------------------------------------------------

package body binaryio is

  ------------------------------------------------------------------------------
  --! read from binary file -> std_logic_vector (no incomplete)
  ------------------------------------------------------------------------------

  procedure read (
    file bin_file : binary_file_t;
    word          : out std_logic_vector
  ) is

    variable v_empty : natural;

  begin

    read(bin_file, word, v_empty);

    assert v_empty = 0
      report "End of file reached before read completed"
      severity error;

  end procedure read;

  ------------------------------------------------------------------------------
  --! read from binary file -> std_logic_vector (incomplete allowed)
  ------------------------------------------------------------------------------

  procedure read (
    file bin_file : binary_file_t;
    word          : out std_logic_vector;
    empty         : out natural
  ) is

    variable v_word : unsigned(word'range);

  begin

    read(bin_file, v_word, empty);

    word := std_logic_vector(v_word);

  end procedure read;

  ------------------------------------------------------------------------------
  --! write to binary file <- std_logic_vector
  ------------------------------------------------------------------------------

  procedure write (
    file bin_file : binary_file_t;
    word          : std_logic_vector
  ) is
  begin

    write(bin_file, unsigned(word));

  end procedure write;

  ------------------------------------------------------------------------------
  --! read an unsigned value -> unsigned (no incomplete)
  ------------------------------------------------------------------------------

  procedure read (
    file bin_file : binary_file_t;
    word          : out unsigned
  ) is

    variable v_empty : natural;

  begin

    read(bin_file, word, v_empty);

    assert v_empty = 0
      report "End of file reached before read completed"
      severity error;

  end procedure read;

  ------------------------------------------------------------------------------
  --! read an unsigned value -> unsigned (incomplete allowed)
  ------------------------------------------------------------------------------

  procedure read (
    file bin_file : binary_file_t;
    word          : out unsigned;
    empty         : out natural
  ) is

    constant c_N_BYTES      : positive := div_ceil(word'length, 8);
    variable v_aligned_word : unsigned(c_N_BYTES * 8 - 1 downto 0);
    variable v_cur_byte     : byte;
    variable v_bit_pos      : integer;

  begin

    empty := 0;

    -- read bytes
    for i in 0 to c_N_BYTES - 1 loop

      if (not endfile(bin_file)) then
        read(bin_file, v_cur_byte);
        v_aligned_word(v_aligned_word'left - (i * 8) downto
        v_aligned_word'length - (i + 1) * 8) := to_unsigned(byte'pos(v_cur_byte), 8);
      else
        empty                                  := c_N_BYTES - i;
        v_aligned_word(8 * empty - 1 downto 0) := (others => '0');
        exit;
      end if;

    end loop;

    word := resize(v_aligned_word, word'length);

  end procedure read;

  ------------------------------------------------------------------------------
  --! write to binary file <- unsigned
  ------------------------------------------------------------------------------

  procedure write (
    file bin_file : binary_file_t;
    word          : unsigned
  ) is

    constant c_N_BYTES      : positive := div_ceil(word'length, 8);
    variable v_aligned_word : unsigned(c_N_BYTES * 8 - 1 downto 0);
    variable v_cur_byte     : byte;

  begin

    v_aligned_word := resize(word, v_aligned_word'length);

    for i in 0 to c_N_BYTES - 1 loop

      v_cur_byte := byte'val(to_integer(v_aligned_word(v_aligned_word'left - (i * 8)
                                                       downto v_aligned_word'length - (i + 1) * 8)));
      write(bin_file, v_cur_byte);
    end loop;

  end procedure write;

end package body binaryio;

----------------------------------------------------------------------------------------------------
