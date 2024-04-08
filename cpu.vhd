-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2023 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Zhdanovich Iaroslav xzhdan00
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic := '0';                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic := '0'                      -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

 --  PC
    signal pc_value : std_logic_vector(12 downto 0);
    signal pc_inc : std_logic;
    signal pc_dec : std_logic;
    signal pc_rst : std_logic;

 --  PTR
    signal ptr_value : std_logic_vector(12 downto 0);
    signal ptr_inc : std_logic;
    signal ptr_dec : std_logic;
    signal ptr_rst : std_logic;

 --  MX1
    signal mx1_value : std_logic_vector(12 downto 0);
    signal mx1_select : std_logic;

 --  MX2
    signal mx2_value : std_logic_vector(7 downto 0);
    signal mx2_select : std_logic_vector(1 downto 0);

 --  FSM
    type fsm_state is (SIDLE, SFETCHi, SDONE, SDECODEi, SREADYi, 
                      SFETCH, SDECODE, SWAIT,
                      SVINC, SVINC_MX, SVINC_EX, 
                      SVDEC, SVDEC_MX, SVDEC_EX, 
                      SPTRDEC, 
                      SPTRINC, 
                      SPRINT, SPRINTWAIT, SPRINTDONE,
                      SINPUT, SINPUTWAIT, SINPUTEXECUTE, SINPUTDONE);
                      
    signal pstate : fsm_state := SIDLE;
    signal nstate : fsm_state := SIDLE;

  begin

 --  Present State register
    pstatereg: process(RESET, CLK)
    begin
      if (RESET='1') then
        pstate <= SIDLE;
      elsif (CLK'event) and (CLK='1') then
        if (EN = '1') then
          pstate <= nstate;
        end if;
      end if;
    end process;

    --  Next State logic + output logic
    nstate_logic: process(pstate, RESET, EN, OUT_BUSY, IN_VLD)
    begin
      pc_rst <= '0'; 
      ptr_rst <= '0';
      pc_inc <= '0';
      pc_dec <= '0';
      ptr_inc <= '0';
      ptr_dec <= '0';
      DATA_RDWR <= '0';
      DATA_EN <= '0';
      OUT_WE <= '0';
      case pstate is

    -- Výchozí stav     
        when SIDLE =>                   
          IN_REQ <= '0';
          mx2_select <= "00";
          DONE <= '0';
          READY <= '0';
          mx1_select <= '0';
          pc_rst <= '1';
          ptr_rst <= '1';
          nstate <= SFETCHi;
        
    -- Inicializační stavy
        when SFETCHi =>
          mx1_select <= '0';
          DATA_EN <= '1';
          nstate <= SDECODEi;

        when SDECODEi =>
          DATA_EN <= '1';
          if DATA_RDATA = X"40" then
            nstate <= SREADYi;
          else
            ptr_inc <= '1';
            nstate <= SFETCHi;
          end if;

        when SREADYi =>
          mx1_select <= '1';
          READY <= '1';
          -- DATA_EN <= '1';
          nstate <= SWAIT;
      
    -- Synchronizační pomocný stav
        when SWAIT =>
          mx1_select <= '1';
          DATA_EN <= '1';
          nstate <= SFETCH;

    -- Načtení instrukcí
        when SFETCH =>
          mx1_select <= '1';
          DATA_EN <= '1';
          nstate <= SDECODE;

    -- Dekódování instrukcí    
        when SDECODE =>
          DATA_EN <= '1';
          pc_inc <= '1';
          case DATA_RDATA is
            when X"2B" =>
              nstate <= SVINC;
              mx1_select <= '0';
            when X"2D" =>
              nstate <= SVDEC;
              mx1_select <= '0';
            when X"3E" =>
              nstate <= SPTRINC;
            when X"3C" =>
              nstate <= SPTRDEC;
            when X"2E" =>
              nstate <= SPRINT;
              mx1_select <= '0';
            when X"2C" =>
              nstate <= SINPUT;
              mx1_select <= '0';
            when X"40" =>
              nstate <= SDONE;
            when others =>
              nstate <= SFETCH;
          end case;
        
    -- Inkrementace hodnoty aktuální buňky (*ptr += 1;)     
        when SVINC =>
          DATA_RDWR <= '0';
          DATA_EN <= '1';
          nstate <= SVINC_MX;
        
        when SVINC_MX =>
          mx2_select <= "11";
          nstate <= SVINC_EX;

        when SVINC_EX =>
          mx1_select <= '1';
          DATA_RDWR <= '1';
          DATA_EN <= '1';
          nstate <= SWAIT;
        
    --  Dekrementace hodnoty aktuální buňky (*ptr -= 1;)
        when SVDEC =>
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          nstate <= SVDEC_MX;
        
        when SVDEC_MX =>
          mx2_select <= "10";
          nstate <= SVDEC_EX;

        when SVDEC_EX =>
          mx1_select <= '1';
          DATA_RDWR <= '1';
          DATA_EN <= '1';
          nstate <= SWAIT;  
        
    -- Inkrementace hodnoty ukazatele (ptr += 1;)     
        when SPTRINC =>
          ptr_inc <= '1';
          nstate <= SWAIT;

    -- Dekrementace hodnoty ukazatele (ptr -= 1;)
        when SPTRDEC =>
          ptr_dec <= '1';
          nstate <= SWAIT;

    -- Vytiskni hodnotu aktuální buňky (putchar(*ptr);)    
        when SPRINT =>
            DATA_RDWR <= '0';
            DATA_EN <= '1';
            nstate <= SPRINTWAIT;

        when SPRINTWAIT =>
          DATA_EN <= '1';
          if OUT_BUSY = '1' then
            nstate <= SPRINTWAIT;
          else 
            nstate <= SPRINTDONE;
          end if;

        when SPRINTDONE =>
          mx1_select <= '1';
          DATA_EN <= '1';
          OUT_DATA <= DATA_RDATA;
          OUT_WE <= '1';
          nstate <= SWAIT;

    -- Načti hodnotu a ulož ji do aktuální buňky (*ptr = getchar();)
        when SINPUT =>
          mx2_select <= "01";
          IN_REQ <= '1';
          nstate <= SINPUTWAIT;

        when SINPUTWAIT =>
          if IN_VLD = '0' then
            nstate <= SINPUTWAIT;
          else 
            nstate <= SINPUTEXECUTE;
          end if;

        when SINPUTEXECUTE =>
          DATA_RDWR <= '1';
          DATA_EN <= '1';
          nstate <= SINPUTDONE;
        
        when SINPUTDONE =>
          IN_REQ <= '0';
          mx1_select <= '1';
          DATA_EN <= '1';
          nstate <= SWAIT;

    -- Zastavení vykonávání programu (return;)
          when SDONE =>
            DONE <= '1';          
          

      end case;
    end process;


    -- Programový čítač
    PC: process (CLK, pc_inc, pc_dec, RESET)
    begin
      if RESET = '1' then
        pc_value <= (others => '0');
      elsif CLK'event and (CLK = '1') then
        if (pc_rst = '1') then 
          pc_value <= (others => '0');  
        elsif (pc_inc = '1') then
          pc_value <= pc_value + 1;
        elsif (pc_dec = '1') then
          pc_value <= pc_value - 1;
        end if;
      end if;
    end process;
    
    -- Ukazatel do paměti dat
    PTR: process (CLK, ptr_inc, ptr_dec, RESET)
    begin
      if RESET = '1' then
        ptr_value <= (others => '0');
      elsif CLK'event and (CLK = '1') then
        if (ptr_rst = '1') then
          ptr_value <= (others => '0');  
        elsif (ptr_inc = '1') then
          ptr_value <= ptr_value + 1;
        elsif (ptr_dec = '1') then
          ptr_value <= ptr_value - 1;
        end if;
      end if;
    end process;

    -- Multiplexor MX1
    MX1: process (CLK, mx1_select, RESET)
    begin
      if RESET = '1' then
        mx1_value <= (others => '0'); 
      elsif CLK'event and (CLK = '1') then
        if (mx1_select = '0') then 
          mx1_value <= ptr_value;
        elsif (mx1_select = '1') then
          mx1_value <= pc_value;
        end if;
      end if;
    end process; 

    DATA_ADDR <= mx1_value;

    -- Multiplexor MX1
    MX2: process (CLK, mx2_select, RESET)
    begin
      if RESET = '1' then
        mx2_value <= (others => '0'); 
      elsif CLK'event and (CLK = '1') then
        case mx2_select is
          when "01" =>
            mx2_value <= IN_DATA;
          when "10" =>
            mx2_value <= DATA_RDATA - 1; 
          when "11" => 
            mx2_value <= DATA_RDATA + 1;
          when others =>
            mx2_value <= (others => '0');
        end case;
      end if;
    end process;

    DATA_WDATA <= mx2_value;

end behavioral;