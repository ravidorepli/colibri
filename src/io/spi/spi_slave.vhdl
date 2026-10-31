--! @title Serial Peripheral Interface Slave
--! @file spi_slave.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 31-01-2025
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

entity spi_slave is
  generic (
    g_WORD_SIZE    : positive  := 8;
    g_SCK_POLARITY : std_logic := '0'; --! 0 -> active high
    g_SCK_PHASE    : std_logic := '0'  --! 0 -> rising edge
  );
  port (
    clk_i       : in    std_logic;
    --! @virtualbus SPI @dir inout
    miso_o      : out   std_logic; --! Master In Slave Out
    mosi_i      : in    std_logic; --! Master Out Slave In
    cs_n_i      : in    std_logic; --! Chip Select (active low)
    sck_i       : in    std_logic; --! SPI clock
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
end entity spi_slave;

architecture rtl of spi_slave is

  type spi_t is record
    mosi : std_logic;
    cs_n : std_logic;
    sck  : std_logic;
  end record spi_t;

  signal spi_if : spi_t;

  type fsm_t is (S_IDLE, S_SELECT, S_TRANSACTION, S_DESELECT);

  type sig_t is record
    state  : fsm_t;
    oshift : snk_data_i'subtype; -- mosi
    odata  : snk_data_i'subtype; -- reg
    ishift : src_data_o'subtype; -- miso
    sck    : std_logic;
    count  : integer range 0 to g_WORD_SIZE - 1;
    valid  : std_logic;
    ready  : std_logic;
  end record sig_t;

  constant c_FSM_INIT : sig_t :=
  (
    state  => S_IDLE,
    oshift => (others => '0'),
    odata  => (others => '0'),
    ishift => (others => '0'),
    sck    => '0',
    count  => 0,
    valid  => '0',
    ready  => '0'
  );

  signal sck_sync : std_logic;
  signal rcmb     : sig_t;
  signal rreg     : sig_t := c_FSM_INIT;

begin

  -- synchronizers for the inputs
  cs_synchro_inst : entity colibri.synchro
    generic map (
      g_DATA_LENGTH => 1,
      g_INIT_VALUE  => (0 => '1')
    )
    port map (
      clk_i     => clk_i,
      reset_i   => '0',
      data_i    => (others => cs_n_i),
      data_o(0) => spi_if.cs_n
    );

  --! SPI clock synchronizer
  sck_synchro_inst : entity colibri.synchro
    generic map (
      g_DATA_LENGTH => 1,
      g_INIT_VALUE  => (0 => g_SCK_POLARITY)
    )
    port map (
      clk_i     => clk_i,
      reset_i   => '0',
      data_i    => (others => sck_i),
      data_o(0) => sck_sync
    );

  --! invert SPI clock if required
  spi_if.sck <= not sck_sync when g_SCK_POLARITY else
                sck_sync;

  mosi_synchro_inst : entity colibri.synchro
    generic map (
      g_DATA_LENGTH => 1
    )
    port map (
      clk_i     => clk_i,
      reset_i   => '0',
      data_i    => (others => mosi_i),
      data_o(0) => spi_if.mosi
    );

  rreg <= rcmb when rising_edge(clk_i);

  -- main fsm
  proc_fsm_cmb : process (all) is

    variable v_int : sig_t;

  begin

    v_int       := rreg;
    v_int.sck   := spi_if.sck;
    v_int.valid := '0';

    case rreg.state is

      when S_IDLE =>
        v_int.count := 0;
        v_int.ready := '1';
        -- save input
        if ((snk_valid_i = '1' or spi_if.cs_n = '0') and rreg.ready = '1') then
          v_int.ready  := '0';
          v_int.ishift := snk_data_i;
          v_int.state  := S_SELECT;
        end if;

      when S_SELECT =>
        -- transaction start

        if (spi_if.cs_n = '0') then
          if (g_SCK_PHASE = '0') then
            v_int.state := S_TRANSACTION;
          else
            if (v_int.sck and not rreg.sck) then
              v_int.state := S_TRANSACTION;
            end if;
          end if;
        end if;

      when S_TRANSACTION =>
        -- rising edge of sck
        if (v_int.sck and not rreg.sck) then
          if (g_SCK_PHASE = '1') then
            v_int.ishift := rreg.ishift(g_WORD_SIZE - 2 downto 0) & '0';         -- shift out
            if (rreg.count < g_WORD_SIZE - 1) then
              v_int.count := rreg.count + 1;
            else
              -- last bit received
              v_int.state := S_DESELECT;
              v_int.odata := rreg.oshift;
              v_int.valid := '1';
            end if;
          else
            v_int.oshift := rreg.oshift(g_WORD_SIZE - 2 downto 0) & spi_if.mosi; -- shift in
          end if;
        end if;

        -- falling edge of sck
        if (not v_int.sck and rreg.sck) then
          if (g_SCK_PHASE = '0') then
            v_int.ishift := rreg.ishift(g_WORD_SIZE - 2 downto 0) & '0';         -- shift out
            if (rreg.count < g_WORD_SIZE - 1) then
              v_int.count := rreg.count + 1;
            else
              v_int.state := S_DESELECT;
              v_int.odata := rreg.oshift;
              v_int.valid := '1';
            end if;
          else
            v_int.oshift := rreg.oshift(g_WORD_SIZE - 2 downto 0) & spi_if.mosi; -- shift in
            -- last shift in
            if (rreg.count = g_WORD_SIZE - 1) then
              v_int.state := S_DESELECT;
              v_int.odata := v_int.oshift;
              v_int.valid := '1';
            end if;
          end if;
        end if;

      when S_DESELECT =>
        -- wait for cs_n to be deasserted
        v_int.valid := '0';

    end case;

    if (spi_if.cs_n = '1') then
      v_int := c_FSM_INIT;
    end if;

    rcmb <= v_int;

  end process proc_fsm_cmb;

  -- output wiring
  src_data_o  <= rreg.odata;
  src_valid_o <= rreg.valid;
  snk_ready_o <= rreg.ready;
  miso_o      <= rreg.ishift(g_WORD_SIZE - 1);

end architecture rtl;
