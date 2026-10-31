--! @file mem_pkg.vhdl
--! @brief Utility Package for Memory Components
--! @author Alberto Perro
--! @version 0.1
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library std;
  use std.textio.all;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;

package mem is

  impure function init_mem_hex (
    filename : string;
    word_size : natural;
    ram_size : natural;
    init_word : std_logic_vector
  ) return slv_array_t;

  impure function init_mem_hex (
    filename : string;
    cell_size : natural;
    word_size : natural;
    ram_size : natural;
    init_word : std_logic_vector
  ) return slv_array_2d_t;

end package mem;

package body mem is

  impure function init_mem_hex (
    filename : string;
    word_size : natural;
    ram_size : natural;
    init_word : std_logic_vector
  ) return slv_array_t is

    variable v_ram       : slv_array_t(0 to ram_size - 1)(word_size - 1 downto 0);
    file     hex_file    : text;
    variable v_text_line : line;
    variable v_read_ok   : boolean;
    variable v_word      : std_logic_vector(word_size - 1 downto 0);
    variable v_word_idx  : natural := 0;

  begin

    if (filename = "") then
      v_word := std_logic_vector(resize(unsigned(init_word), word_size));
      v_ram  := (others => v_word);
    else
      file_open(hex_file, filename, read_mode);

      while not endfile(hex_file) loop
        readline(hex_file, v_text_line);
        hread(v_text_line, v_word, v_read_ok);

        if (v_read_ok and v_word_idx < ram_size) then
          v_ram(v_word_idx) := v_word;
          v_word_idx        := v_word_idx + 1;
        else
          exit;
        end if;

      end loop;

    end if;

    return v_ram;

  end function init_mem_hex;

  impure function init_mem_hex (
    filename : string;
    cell_size : natural;
    word_size : natural;
    ram_size : natural;
    init_word : std_logic_vector
  ) return slv_array_2d_t is

    variable v_ram       : slv_array_2d_t(0 to ram_size - 1)(0 to word_size - 1)(cell_size - 1 downto 0);
    file     hex_file    : text;
    variable v_text_line : line;
    variable v_read_ok   : boolean;
    variable v_word_slv  : std_logic_vector(word_size * cell_size - 1 downto 0);
    variable v_word      : slv_array_t(0 to word_size - 1)(cell_size - 1 downto 0);
    variable v_word_idx  : natural := 0;

  begin

    if (filename = "") then

      for i in 0 to word_size - 1 loop
        v_word(i) := std_logic_vector(resize(unsigned(init_word), cell_size));
      end loop;

      v_ram := (others => v_word);
    else
      file_open(hex_file, filename, read_mode);

      while not endfile(hex_file) loop
        readline(hex_file, v_text_line);
        hread(v_text_line, v_word_slv, v_read_ok);

        if (v_read_ok and v_word_idx < ram_size) then
          v_ram(v_word_idx) := slv_to_slv_array(v_word_slv, cell_size);
          v_word_idx        := v_word_idx + 1;
        else
          exit;
        end if;

      end loop;

    end if;

    return v_ram;

  end function init_mem_hex;

end package body mem;
