--MIT License
--
--Copyright (c) 2019 Fekete Balázs Valér
--
--Permission is hereby granted, free of charge, to any person obtaining a copy
--of this software and associated documentation files (the "Software"), to deal
--in the Software without restriction, including without limitation the rights
--to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--copies of the Software, and to permit persons to whom the Software is
--furnished to do so, subject to the following conditions:
--
--The above copyright notice and this permission notice shall be included in all
--copies or substantial portions of the Software.
--
--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--SOFTWARE.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

entity bram_dsp_mac_TB is
--  Port ( );
end bram_dsp_mac_TB;

architecture Behavioral of bram_dsp_mac_TB is

    component matrix_core is
    Generic (log2Acols : integer;
             log2Brows : integer;
             log2depth : integer;
             dataWidthAB : integer;
             dataWidthC : integer); --2*dataWidthAB + 2**log2depth - 1
    Port ( clock : in STD_LOGIC;

           --init signals
           load_in, validA_in, validB_in, validC_in : in STD_LOGIC;
           addrA_in : in STD_LOGIC_VECTOR(log2Acols+log2depth-1 downto 0);
           addrB_in : in STD_LOGIC_VECTOR(log2Brows+log2depth-1 downto 0);
           addrC_in : in STD_LOGIC_VECTOR(log2Acols+log2Brows-1 downto 0);
           a_in : in STD_LOGIC_VECTOR (dataWidthAB-1 downto 0);
           b_in : in STD_LOGIC_VECTOR (dataWidthAB-1 downto 0);
           c_in : in STD_LOGIC_VECTOR (dataWidthC-1 downto 0);

           --result signals
           cReady_out : out STD_LOGIC;
           readC_in : in STD_LOGIC;
           c_out : out STD_LOGIC_VECTOR (dataWidthC-1 downto 0));
    end component;
    
-- for first test case set:
--    constant log2Acols : integer := 2;
--    constant log2Brows : integer := 2;
--    constant log2depth : integer := 3;
--    constant dataWidthAB : integer := 8;
      --2*dataWidthAB + 2**log2depth - 1
--    constant dataWidthC : integer := 24;

-- for second test case set:
--    constant log2Acols : integer := 2;
--    constant log2Brows : integer := 2;
--    constant log2depth : integer := 4;
--    constant dataWidthAB : integer := 8;
      --2*dataWidthAB + 2**log2depth - 1
--    constant dataWidthC : integer := 24;

-- for third test case set:
    constant log2Acols : integer := 3;
    constant log2Brows : integer := 3;
    constant log2depth : integer := 4;
    constant dataWidthAB : integer := 8;
     --2*dataWidthAB + 2**log2depth - 1
    constant dataWidthC : integer := 24;
    
    signal clock :  STD_LOGIC;
    signal load_in, validA_in, validB_in, validC_in :  STD_LOGIC := '0';
    signal addrA_in :  STD_LOGIC_VECTOR(log2Acols+log2depth-1 downto 0);
    signal addrB_in :  STD_LOGIC_VECTOR(log2Brows+log2depth-1 downto 0);
    signal addrC_in :  STD_LOGIC_VECTOR(log2Acols+log2Brows-1 downto 0);
    signal a_in :  STD_LOGIC_VECTOR (dataWidthAB-1 downto 0);
    signal b_in :  STD_LOGIC_VECTOR (dataWidthAB-1 downto 0);
    signal c_in :  STD_LOGIC_VECTOR (dataWidthC-1 downto 0);
    signal cReady_out :  STD_LOGIC;
    signal readC_in :  STD_LOGIC := '0';
    signal c_out :  STD_LOGIC_VECTOR (dataWidthC-1 downto 0);
    
    signal reset :  STD_LOGIC;
    signal counter :  STD_LOGIC_VECTOR(log2Acols+log2depth downto 0);

begin

    DUT_inst : matrix_core
    Generic map (log2Acols, log2Brows, log2depth, dataWidthAB, dataWidthC)
    Port map(clock, load_in, validA_in, validB_in, validC_in, addrA_in, addrB_in, addrC_in, a_in, b_in, c_in, cReady_out, readC_in, c_out);


    process begin
        clock <= '0';
        wait for 5 ns;
        clock <= '1';
        wait for 5 ns;
    end process;
    
    process begin
       reset <= '1';
       wait for 100 ns;
       reset <= '0';
       wait;
    end process;
    
    process(clock) begin
        if rising_edge(clock) then
            if reset = '1' then
                counter <= (others => '0');
                load_in <= '0';
                validA_in <= '0';
                validB_in <= '0';
                validC_in <= '0';
                readC_in <= '0';
            elsif conv_integer(counter) < 2**(log2Acols+log2depth) then
                validA_in <= '1';
                validB_in <= '1';
                validC_in <= '1';
                load_in <= '1';
                counter <= counter + '1';
            else
                validA_in <= '0';
                validB_in <= '0';
                validC_in <= '0';
                load_in <= '0';
            end if;
            addrA_in <= counter(log2Acols+log2depth-1 downto 0);
            addrB_in <= counter(log2Brows+log2depth-1 downto 0);
            addrC_in <= counter(log2Acols+log2Brows-1 downto 0);
-- uncomment for 1st test case
--            a_in <= ("00" & counter) + '1';
--            b_in <= x"40" - ("00" & counter);
--            c_in <= x"0000" & "00" & counter;

-- uncomment for 2nd test case
--            a_in <= ("0" & counter) + '1';
--            b_in <= x"40" - ("0" & counter);
--            c_in <= x"0000" & "0" & counter;
            
-- uncomment for 3rd test case           
            a_in <= counter + '1';
            b_in <= x"40" - counter;
            c_in <= x"0000" & counter;
       end if;
    end process;
 
-- Expected matrices: C += A * B'

-- 1st  

-- 8311 10134 11957 13780
-- 5971  7282  8593  9904
-- 3631  4430  5229  6028
-- 1291  1578  1865  2152

-- 2nd

--  7392    5217    3042     867
-- 21860   15589    9318    3047
-- 36328   25961   15594    5227
-- 50796   36333   21870    7407

-- 3rd

--   7408     5233     3058      883    33268    31349    29174    26999
--- 21880    15609     9338     3067    92796    90877    84606    78335
--  36352    25985    15618     5251   152324   150405   140038   129671
--  50824    36361    21898     7435   211852   209933   195470   181007
--  65296    46737    28178     9619   271380   269461   250902   232343
--  79768    57113    34458    11803   330908   328989   306334   283679
--  94240    67489    40738    13987   390436   388517   361766   335015
-- 108712    77865    47018    16171   449964   448045   417198   386351

end Behavioral;
