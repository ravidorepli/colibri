--! @title Encoding functions
--! @file encoders.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 30-11-2023
--! @version 0.1

--! Some of the work was inspired by the PoC Library (https://github.com/VLSI-EDA/PoC)
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
  use colibri.utils.all;

package encoders is

  --! encode binary coded value in gray code
  function bin2gray (arg : unsigned) return std_logic_vector;

  --! decode gray coded value in binary code
  function gray2bin (arg : std_logic_vector) return unsigned;

  --! encode binary coded value in gray code
  function bin2gray (arg : natural; max : natural) return std_logic_vector;

  --! decode gray coded value in binary code
  function gray2bin (arg : std_logic_vector) return natural;

  --! encode binary coded value in one hot code
  function bin2onehot (arg : unsigned) return std_logic_vector;

  --! decode one hot coded value in binary code
  function onehot2bin (arg : std_logic_vector) return unsigned;

  --! encode binary coded value in one hot code with reduced states
  function bin2onehot (arg : unsigned; max : positive) return std_logic_vector;

  --! decode one hot coded value in binary code with reduced states
  function onehot2bin (arg : std_logic_vector; max : positive) return unsigned;

  --! encode binary value in binary coded decimal (BCD)
  function bin2bcd (arg : unsigned) return std_logic_vector;

  --! encode binary coded decimal (BCD) in binary
  function bcd2bin (arg : std_logic_vector) return unsigned;

  --! priority encoder
  function priority_encode (arg : std_logic_vector) return unsigned;

end package encoders;

package body encoders is

  --! encode binary coded value in gray code
  function bin2gray (arg : unsigned) return std_logic_vector is

    variable v_ret : std_logic_vector(arg'range);

  begin

    v_ret := ('0' & std_logic_vector(arg(arg'left downto 1))) xor std_logic_vector(arg);
    return v_ret;

  end function bin2gray;

  --! decode gray coded value in binary code
  function gray2bin (arg : std_logic_vector) return unsigned is

    variable v_ret : unsigned(arg'range);

  begin

    v_ret := unsigned(arg);

    for i in arg'length - 2 downto 0 loop
      v_ret(i) := v_ret(i + 1) xor v_ret(i);
    end loop;

    return v_ret;

  end function gray2bin;

  --! encode binary coded value in gray code
  function bin2gray (arg : natural; max : natural) return std_logic_vector is

    variable v_uns : unsigned(log2ceil(max) - 1 downto 0);

  begin

    v_uns := to_unsigned(arg, v_uns'length);
    return bin2gray(v_uns);

  end function bin2gray;

  --! decode gray coded value in binary code
  function gray2bin (arg : std_logic_vector) return natural is
  begin

    return to_integer(gray2bin(arg));

  end function gray2bin;

  --! encode binary coded value in one hot code
  function bin2onehot (arg : unsigned) return std_logic_vector is

    variable v_ret : std_logic_vector((2 ** arg'length) - 1 downto 0);

  begin

    for i in 0 to v_ret'length - 1 loop

      if (i = arg) then
        v_ret(i) := '1';
      else
        v_ret(i) := '0';
      end if;

    end loop;

    return v_ret;

  end function bin2onehot;

  --! decode one hot coded value in binary code
  function onehot2bin (arg : std_logic_vector) return unsigned is

    variable v_ret : unsigned(log2ceil(arg'length) - 1 downto 0);

  begin

    for i in 0 to arg'length - 1 loop

      if (arg(i) = '1') then
        v_ret := to_unsigned(i, v_ret'length);
      end if;

    end loop;

    return v_ret;

  end function onehot2bin;

  --! encode binary coded value in one hot code with reduced states
  function bin2onehot (arg : unsigned; max : positive) return std_logic_vector is

    variable v_ret : std_logic_vector(max - 1 downto 0);

  begin

    for i in 0 to v_ret'length - 1 loop

      if (i = arg) then
        v_ret(i) := '1';
      else
        v_ret(i) := '0';
      end if;

    end loop;

    return v_ret;

  end function bin2onehot;

  --! decode one hot coded value in binary code with reduced states
  function onehot2bin (arg : std_logic_vector; max : positive) return unsigned is

    variable v_ret : unsigned(log2ceil(max) - 1 downto 0);

  begin

    for i in 0 to arg'length - 1 loop

      if (arg(i) = '1') then
        v_ret := to_unsigned(i, v_ret'length);
      end if;

    end loop;

    return v_ret;

  end function onehot2bin;

  --! encode binary value in binary coded decimal (BCD)
  function bin2bcd (arg : unsigned) return std_logic_vector is
  begin

    assert arg < 10
      report "binary overflow bcd"
      severity warning;

    return std_logic_vector(resize(arg, 4));

  end function bin2bcd;

  --! encode binary coded decimal (BCD) in binary
  function bcd2bin (arg : std_logic_vector) return unsigned is

  begin

    assert arg'length = 4
      report "not a valid bcd number"
      severity failure;

    return unsigned(arg);

  end function bcd2bin;

  --! priority encoder
  function priority_encode (arg : std_logic_vector) return unsigned is

    variable v_res : unsigned(log2ceil(arg'length) - 1 downto 0);

  begin

    v_res := (others => '0');

    for i in arg'range loop

      if (arg(i) = '1') then
        v_res := to_unsigned(i, v_res'length);
        return v_res;
      end if;

    end loop;

    return v_res;

  end function priority_encode;

end package body encoders;
