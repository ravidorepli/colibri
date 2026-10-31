--! @title Binary Content Addressable Memory
--! @file bicam.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 15-10-2024
--! @version 0.1

--! @details
--! This entity implements a simple binary content addressable memory.
--! Write: when `wrreq` is asserted and the cam is not `full`, `data` is sampled and written onto the cam.
--!        Writing takes one clock cycle, busy is asserted and no input is sampled.
--! Clear: same as a write operation, but the `clear` signal is also asserted with `wrreq`.
--!        The matched word is deleted and in the next clock cycle the old address is put in the `addr` line.
--! Read: when `rdreq` is asserted, `data` is sampled and the cam is searched for a match.
--!       If a match is found, the address is put on `addr` and `match` is asserted in the next clock cycle.
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
  use colibri.encoders.all;
  use colibri.types.all;

entity bicam is
  generic (
    --! words
    g_N_WORDS    : positive;
    --! data word size
    g_DATA_WIDTH : positive
  );
  port (
    clk_i   : in    std_logic;                                   --! clock
    reset_i : in    std_logic;                                   --! reset_i
    rdreq_i : in    std_logic;                                   --! read request
    wrreq_i : in    std_logic;                                   --! write request
    clear_i : in    std_logic;                                   --! clear word (asserted with wrreq)
    data_i  : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0); --! data_i to write/search
    full_o  : out   std_logic;                                   --! cam address space is full
    busy_o  : out   std_logic;                                   --! cam is busy writing, incoming requests are ignored
    match_o : out   std_logic;                                   --! match data_i
    addr_o  : out   unsigned(log2ceil(g_N_WORDS) - 1 downto 0)   --! address written or read
  );
end entity bicam;

architecture rtl of bicam is

  signal cam : slv_array_t(0 to g_N_WORDS - 1)(g_DATA_WIDTH - 1 downto 0);

  type sig_t is record
    used_vec : std_logic_vector(g_N_WORDS - 1 downto 0);
    addr     : unsigned(log2ceil(g_N_WORDS) - 1 downto 0);
    data     : std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    match    : std_logic;
    write    : std_logic;
  end record sig_t;

  signal rreg : sig_t;
  signal rcmb : sig_t;

  constant c_SIG_INIT : sig_t :=
  (
    used_vec => (others => '0'),
    addr     => (others => '0'),
    data     => (others => '0'),
    match    => '0',
    write    => '0'
  );

  --! find first available empty cell
  function find_first (vec : std_logic_vector) return unsigned is

    variable v_res : unsigned(log2ceil(vec'length) - 1 downto 0);

  begin

    v_res := (others => '0');

    for i in vec'range loop

      if (vec(i) = '0') then
        v_res := to_unsigned(i, v_res'length);
      end if;

    end loop;

    return v_res;

  end function find_first;

begin

  rreg <= rcmb when rising_edge(clk_i);

  proc_fsm : process (all) is

    variable v_int : sig_t;

  begin

    v_int       := rreg;
    v_int.match := '0';
    v_int.addr  := (others => '0');
    v_int.write := '0';

    if (reset_i) then
      v_int.used_vec := (others => '0');
      v_int.data     := (others => '0');
    else
      -- WRITE TO CAM CELL (2nd cycle)
      if (rreg.write = '1') then
        v_int.write                           := '0';
        v_int.addr                            := (others => '0');
        v_int.used_vec(to_integer(rreg.addr)) := '1';

      -- CLEAR MATCHING CAM CELL
      elsif (wrreq_i and clear_i) then

        for i in 0 to g_N_WORDS - 1 loop
          if (rreg.used_vec(i) = '1') then
            if (cam(i) = data_i) then
              v_int.match       := '1';
              v_int.used_vec(i) := '0';
              v_int.addr        := to_unsigned(i, addr_o'length);
            end if;
          end if;
        end loop;

      -- WRITE TO FIRST AVAILABLE CAM CELL (1st cycle)
      elsif (wrreq_i and not full_o) then
        -- find empty slot
        if (rreg.used_vec = (rreg.used_vec'range => '0')) then
          v_int.addr := (others => '0');
        else
          v_int.addr := find_first(rreg.used_vec);
        end if;
        v_int.data  := data_i;
        v_int.write := '1';

      -- SEARCH FOR MATCHING CELL
      elsif (rdreq_i) then
        -- find data in cam
        for i in 0 to g_N_WORDS - 1 loop
          if (rreg.used_vec(i) = '1') then
            if (cam(i) = data_i) then
              -- match found
              v_int.match := '1';
              v_int.addr  := to_unsigned(i, addr_o'length);
            end if;
          end if;
        end loop;

      end if;
    end if;

    rcmb <= v_int;

  end process proc_fsm;

  full_o  <= and rreg.used_vec;
  addr_o  <= rreg.addr;
  busy_o  <= rreg.write;
  match_o <= rreg.match;

  proc_write_to_cam : process (clk_i) is
  begin

    if (rising_edge(clk_i) and rreg.write = '1') then
      cam(to_integer(rreg.addr)) <= rreg.data;
    end if;

  end process proc_write_to_cam;

end architecture rtl;
