--! @title Serial Peripheral Interface Master
--! @file spi_master.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 05-02-2025
--! @version 0.1

--! @details
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

entity spi_master is
  generic (
    g_CLOCK_PERIOD  : time;                   --! system clock
    g_SCK_FREQUENCY : natural   := 1_000_000; --! spi clock frequency
    g_WORD_SIZE     : positive  := 8;
    g_SCK_POLARITY  : std_logic := '0';       --! 0 -> active high
    g_SCK_PHASE     : std_logic := '0'        --! 0 -> rising edge
  );
  port (
    clk_i       : in    std_logic;
    --! @virtualbus SPI @dir inout
    miso_i      : in    std_logic; --! Master In Slave Out
    mosi_o      : out   std_logic; --! Master Out Slave In
    cs_n_o      : out   std_logic; --! Chip Select (active low)
    sck_o       : out   std_logic; --! SPI clock
    --! @end
    --! @virtualbus stream @dir out
    src_data_o  : out   std_logic_vector(g_WORD_SIZE - 1 downto 0);
    src_valid_o : out   std_logic;
    --! @end
    --! @virtualbus stream @dir in
    snk_data_i  : in    std_logic_vector(g_WORD_SIZE - 1 downto 0);
    snk_valid_i : in    std_logic;
    snk_ready_o : out   std_logic
  --! @end
  );
end entity spi_master;

architecture rtl of spi_master is

  constant c_SCK_DIV : integer := integer((1 sec / g_SCK_FREQUENCY) / g_CLOCK_PERIOD);

  type spi_t is record
    cs_n : std_logic;
    sck  : std_logic;
  end record spi_t;

  signal spi_miso : std_logic;

  constant c_SPI_DEFAULT : spi_t :=
  (
    cs_n => '1',
    sck  => g_SCK_POLARITY
  );

  type fsm_t is (S_IDLE, S_SELECT, S_TRANSACTION, S_DESELECT);

  type sig_t is record
    state  : fsm_t;
    oshift : snk_data_i'subtype; -- mosi
    odata  : snk_data_i'subtype; -- reg
    ishift : src_data_o'subtype; -- miso
    clkcnt : integer range 0 to c_SCK_DIV / 2 - 1;
    bitcnt : integer range 0 to g_WORD_SIZE - 1;
    spi    : spi_t;
    valid  : std_logic;
    ready  : std_logic;
  end record sig_t;

  constant c_FSM_INIT : sig_t :=
  (
    state  => S_IDLE,
    oshift => (others => '0'),
    odata  => (others => '0'),
    ishift => (others => '0'),
    clkcnt => 0,
    bitcnt => 0,
    spi    => c_SPI_DEFAULT,
    valid  => '0',
    ready  => '0'
  );

  signal rcmb : sig_t;
  signal rreg : sig_t := c_FSM_INIT;

begin

  --! MISO synchronizer
  miso_synchro_inst : entity colibri.synchro
    generic map (
      g_DATA_LENGTH => 1
    )
    port map (
      clk_i     => clk_i,
      reset_i   => '0',
      data_i    => (others => miso_i),
      data_o(0) => spi_miso
    );

  rreg <= rcmb when rising_edge(clk_i);

  -- main fsm
  proc_fsm_cmb : process (all) is

    variable v_int : sig_t;

  begin

    v_int       := rreg;
    v_int.valid := '0';

    -- sck clock division counter
    if (rreg.clkcnt < c_SCK_DIV / 2 - 1) then
      v_int.clkcnt := rreg.clkcnt + 1;
    else
      v_int.spi.sck := not rreg.spi.sck;
      v_int.clkcnt  := 0;
    end if;

    case rreg.state is

      when S_IDLE =>
        v_int.bitcnt   := 0;
        v_int.ready    := '1';
        v_int.spi.cs_n := '1';
        -- keep the spi clock off
        v_int.spi.sck  := '0';
        v_int.clkcnt   := 0;

        -- save input
        if (snk_valid_i = '1' and rreg.ready = '1') then
          v_int.ready  := '0';
          v_int.ishift := snk_data_i;
          if (g_SCK_PHASE = '0') then
            v_int.state := S_TRANSACTION;
          else
            v_int.state := S_SELECT;
          end if;
          v_int.spi.cs_n := '0';
        end if;

      when S_SELECT =>
        -- transaction start
        -- rising edge spi clock
        if (v_int.spi.sck and not rreg.spi.sck) then
          v_int.state := S_TRANSACTION;
        end if;

      when S_TRANSACTION =>
        -- rising edge of sck
        if (v_int.spi.sck and not rreg.spi.sck) then
          if (g_SCK_PHASE = '1') then
            v_int.ishift := rreg.ishift(g_WORD_SIZE - 2 downto 0) & '0';      -- shift out
            if (rreg.bitcnt < g_WORD_SIZE - 1) then
              v_int.bitcnt := rreg.bitcnt + 1;
            else
              -- last bit received
              v_int.state   := S_DESELECT;
              v_int.odata   := rreg.oshift;
              v_int.valid   := '1';
              -- stop the clock
              v_int.clkcnt  := 0;
              v_int.spi.sck := '0';
            end if;
          else
            v_int.oshift := rreg.oshift(g_WORD_SIZE - 2 downto 0) & spi_miso; -- shift in
          end if;
        end if;

        -- falling edge of sck
        if (not v_int.spi.sck and rreg.spi.sck) then
          if (g_SCK_PHASE = '0') then
            v_int.ishift := rreg.ishift(g_WORD_SIZE - 2 downto 0) & '0';      -- shift out
            if (rreg.bitcnt < g_WORD_SIZE - 1) then
              v_int.bitcnt := rreg.bitcnt + 1;
            else
              v_int.state   := S_DESELECT;
              v_int.odata   := rreg.oshift;
              v_int.valid   := '1';
              -- stop the clock
              v_int.clkcnt  := 0;
              v_int.spi.sck := '0';
            end if;
          else
            v_int.oshift := rreg.oshift(g_WORD_SIZE - 2 downto 0) & spi_miso; -- shift in
          end if;
        end if;

      when S_DESELECT =>
        -- disable cs
        v_int.spi.cs_n := '1';
        v_int.valid    := '0';
        -- keep clock off
        v_int.clkcnt   := 0;
        v_int.spi.sck  := '0';
        --
        v_int.state    := S_IDLE;

    end case;

    rcmb <= v_int;

  end process proc_fsm_cmb;

  -- output wiring
  src_data_o  <= rreg.odata;
  src_valid_o <= rreg.valid;
  snk_ready_o <= rreg.ready;
  mosi_o      <= rreg.ishift(g_WORD_SIZE - 1);
  sck_o       <= rreg.spi.sck when g_SCK_POLARITY = '0' else
                 not rreg.spi.sck;
  cs_n_o      <= rreg.spi.cs_n;

end architecture rtl;
