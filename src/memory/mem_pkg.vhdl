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
  -- hread for std_logic_vector: in std_logic_1164 since VHDL-2008, in std_logic_textio before
  -- (Quartus Lite / Standard); the package is empty, but still there, in VHDL-2008 tools
  use ieee.std_logic_textio.all;

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

  --! simple_dpram width / address rules (port A width 0 = g_DATA_WIDTH, port B width 0 = port A,
  --! address width 0 = derived from the widths and g_N_WORDS). A generic whose default depends on
  --! another generic is VHDL-2008, which Quartus Lite / Standard reject: these resolve the 0s.
  function dpram_width_a (data_width : positive; width_a : natural) return positive;
  function dpram_width_b (data_width : positive; width_a : natural; width_b : natural) return positive;
  function dpram_addr_a (data_width : positive; width_a : natural; width_b : natural;
                         n_words : positive; addr_a : natural) return positive;
  function dpram_addr_b (data_width : positive; width_a : natural; width_b : natural;
                         n_words : positive; addr_b : natural) return positive;

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

  function dpram_width_a (data_width : positive; width_a : natural) return positive is
  begin

    return or_default(width_a, data_width);

  end function dpram_width_a;

  function dpram_width_b (data_width : positive; width_a : natural; width_b : natural) return positive is
  begin

    return or_default(width_b, dpram_width_a(data_width, width_a));

  end function dpram_width_b;

  function dpram_addr_a (data_width : positive; width_a : natural; width_b : natural;
                         n_words : positive; addr_a : natural) return positive is

    constant c_A : positive := dpram_width_a(data_width, width_a);
    constant c_B : positive := dpram_width_b(data_width, width_a, width_b);

  begin

    return or_default(addr_a, log2ceil(max_int(c_A, c_B) * n_words / c_A));

  end function dpram_addr_a;

  function dpram_addr_b (data_width : positive; width_a : natural; width_b : natural;
                         n_words : positive; addr_b : natural) return positive is

    constant c_A : positive := dpram_width_a(data_width, width_a);
    constant c_B : positive := dpram_width_b(data_width, width_a, width_b);

  begin

    return or_default(addr_b, log2ceil(max_int(c_A, c_B) * n_words / c_B));

  end function dpram_addr_b;

end package body mem;
