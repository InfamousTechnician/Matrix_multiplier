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

entity matrix_core is
    Generic (log2Acols : integer := 6;
             log2Brows : integer  := 6;
             log2depth : integer := 5;
             dataWidthAB : integer := 12;
             dataWidthC : integer := 48); --2*dataWidthAB + 2**log2depth - 1
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
           c_out : out STD_LOGIC_VECTOR (dataWidthC-1 downto 0)
         );
end matrix_core;

architecture Behavioral of matrix_core is

    --state machines
    type state_T is (empty, load, start, full, flush);
    signal state : state_T;
    signal depthCounter : std_logic_vector(log2depth downto 0);
    signal ABcounter : std_logic_vector(log2Acols+log2Brows-2 downto 0);
    signal ready : std_logic;
    
    constant pipeLength : integer := 7; -- 2 for C write, 2 for C read, 1 for registering ramC output (for performance), 1 for multiply, 1 for accumlate

    --control pipeline
    signal restartPipe : std_logic_vector(pipeLength-1 downto 0);
    
    --block RAM definitions
    type ramA_T is array (2**(log2Acols+log2depth)-1 downto 0) of std_logic_vector(dataWidthAB-1 downto 0);
    type ramB_T is array (2**(log2Brows+log2depth)-1 downto 0) of std_logic_vector(dataWidthAB-1 downto 0);
    type ramC_T is array (2**(log2Acols+log2Brows)-1 downto 0) of std_logic_vector( dataWidthC-1 downto 0);
    signal          ramA : ramA_T;
    signal          ramB : ramB_T;
    shared variable ramC : ramC_T;

    --data pipelines
    type dataPipeAB_T is array (3 downto 0) of std_logic_vector(dataWidthAB-1 downto 0);
    signal colDataPipe0 : dataPipeAB_T;
    signal colDataPipe1 : dataPipeAB_T;
    signal rowDataPipe0 : dataPipeAB_T;
    signal rowDataPipe1 : dataPipeAB_T;
    signal c00 : std_logic_vector(dataWidthC-1 downto 0);
    signal c01 : std_logic_vector(dataWidthC-1 downto 0);
    signal c10 : std_logic_vector(dataWidthC-1 downto 0);
    signal c11 : std_logic_vector(dataWidthC-1 downto 0);
    
    --multiply accumlate signals
    type mult_T is array (3 downto 0) of std_logic_vector(2*dataWidthAB-1 downto 0);
    type accu_T is array (3 downto 0) of std_logic_vector(   dataWidthC-1 downto 0);
    signal mult : mult_T;
    signal accu, accuOut : accu_T;

    --supportive signals
    signal ramCaddr0, ramCaddr1 : std_logic_vector(log2Acols+log2Brows-1 downto 0);
    signal ramCaddrReg00, ramCaddrReg01, ramCaddrReg10, ramCaddrReg11 : std_logic_vector(log2Acols+log2Brows-1 downto 0);
    signal ramCdata0, ramCdata1 : std_logic_vector(dataWidthC-1 downto 0);
    signal ramCout0, ramCout1 : std_logic_vector(dataWidthC-1 downto 0);
    signal ramCwriteEnable0, ramCwriteEnable1 : std_logic;
    signal ramCreg0, ramCreg1 : std_logic_vector(dataWidthC-1 downto 0);
    signal Acol, AcolReg : std_logic_vector(log2Acols-2 downto 0);
    signal Brow, BrowReg : std_logic_vector(log2Brows-2 downto 0);
    signal depth : std_logic_vector(log2depth-1 downto 0);

begin

    process(clock) begin
        if rising_edge(clock) then
            case state is
                when empty =>
                    if load_in = '1' then
                        state <= load;
                        ready <= '0';
                    end if;
                    depthCounter <= (others => '0');
                    ABcounter <= (others => '0');
                when load =>
                    if load_in = '0' then
                        state <= start;
                    end if;
                when start =>
                    if restartPipe(6) = '1' then
                        state <= full;
                    end if;
                    if depthCounter(depthCounter'high ) = '0' then
                        depthCounter <= depthCounter + '1';
                    else
                        depthCounter <= (others => '0');
                    end if;
                when full =>
                    if ABcounter(ABcounter'high) = '1' then
                        state <= flush;
                    end if;
                    if depthCounter(depthCounter'high ) = '0' then
                        depthCounter <= depthCounter + '1';
                    elsif ABcounter(ABcounter'high) = '0' then
                        depthCounter <= (others => '0');
                        ABcounter <= ABcounter + '1';
                    end if;
                when flush =>
                    if restartPipe(6) = '1' then
                        state <= empty;
                        ready <= '1';
                    end if;
                when others =>
                    state <= empty;
            end case;
            if state = empty then
                restartPipe <= (others => '0');
            else
                restartPipe <= restartPipe(restartPipe'high-1 downto 0) & depthCounter(depthCounter'high);
            end if;
        end if;
    end process;
    
    cReady_out <= ready;
    
    Acol <= ABCounter(log2Acols-2+log2Brows-1 downto log2Brows-1);
    Brow <= ABCounter(log2Brows-2 downto 0);
    depth <= depthCounter(depthCounter'high-1 downto 0);
    
    ramCaddr0 <= addrC_in when load_in = '1' else
                 Acol & '0' & Brow & '0' when restartPipe(0) = '1' else
                 Acol & '1' & Brow & '0' when restartPipe(1) = '1' else
                 AcolReg & '0' & BrowReg & '0' when restartPipe(5) = '1' else
                 AcolReg & '1' & BrowReg & '0' when restartPipe(6) = '1' else
                 (others => '0');
    
    ramCaddr1 <= addrC_in - '1' when readC_in = '1' else
                 Acol & '0' & Brow & '1' when restartPipe(0) = '1' else
                 Acol & '1' & Brow & '1' when restartPipe(1) = '1' else
                 AcolReg & '0' & BrowReg & '1' when restartPipe(5) = '1' else
                 AcolReg & '1' & BrowReg & '1' when restartPipe(6) = '1' else
                 (others => '0');

    ramCdata0 <= c_in when validC_in = '1' else
                 accuOut(0) when restartPipe(5) = '1' else
                 accuOut(2) when restartPipe(6) = '1' else
                 (others => '0');
    ramCdata1 <= accuOut(1) when restartPipe(5) = '1' else
                 accuOut(3) when restartPipe(6) = '1' else
                 (others => '0');
    
    process(clock) begin
        if rising_edge(clock) then

            if validA_in = '1' then
                ramA(conv_integer(addrA_in)) <= a_in;
            else
                colDataPipe0 <= colDataPipe0(colDataPipe0'high-1 downto 0) & ramA(conv_integer(Acol & '0' & depth));
                colDataPipe1 <= colDataPipe1(colDataPipe1'high-1 downto 0) & ramA(conv_integer(Acol & '1' & depth));
            end if;
            if validB_in = '1' then
                ramB(conv_integer(addrB_in)) <= b_in;
            else
                rowDataPipe0 <= rowDataPipe0(rowDataPipe0'high-1 downto 0) & ramB(conv_integer(Brow & '0' & depth));
                rowDataPipe1 <= rowDataPipe1(rowDataPipe1'high-1 downto 0) & ramB(conv_integer(Brow & '1' & depth));
            end if;           
            
            if depthCounter(depthCounter'high) = '1' then
                 AcolReg <= Acol;
                 BrowReg <= Brow;
            end if;
            
            if restartPipe(2) = '1' then
                c00 <= ramCout0;
                c01 <= ramCout1;
            end if;

            if restartPipe(3)  = '1' then
                c10 <= ramCout0;
                c11 <= ramCout1;
            end if;

            if readC_in = '1' then
                c_out <= ramCout1;
            end if;

            if restartPipe(3) = '1' then
                mult(0) <= (others => '0');
                mult(1) <= (others => '0');
                mult(2) <= (others => '0');
                mult(3) <= (others => '0');
            else
                mult(0) <= colDataPipe0(colDataPipe0'high) * rowDataPipe0(rowDataPipe0'high);
                mult(1) <= colDataPipe0(colDataPipe0'high) * rowDataPipe1(rowDataPipe1'high);
                mult(2) <= colDataPipe1(colDataPipe1'high) * rowDataPipe0(rowDataPipe0'high);
                mult(3) <= colDataPipe1(colDataPipe1'high) * rowDataPipe1(rowDataPipe1'high);
            end if;

            if restartPipe(4) = '1' then
                accu(0) <= c00 + mult(0);
                accu(1) <= c01 + mult(1);
                accu(2) <= c10 + mult(2);
                accu(3) <= c11 + mult(3);
                accuOut <= accu;
            else
                accu(0) <= accu(0) + mult(0);
                accu(1) <= accu(1) + mult(1);
                accu(2) <= accu(2) + mult(2);
                accu(3) <= accu(3) + mult(3);
            end if;
        end if;
    end process;

    ramCwriteEnable0 <= validC_in when state = empty or state = load else 
                        restartPipe(5) or restartPipe(6) when state = full or state = flush else
                        '0';
    ramCwriteEnable1 <= restartPipe(5) or restartPipe(6) when state = full or state = flush else
                        '0';
                   
    ramC_port0 : process(clock) begin
        if rising_edge(clock) then
            ramCreg0 <= ramC(conv_integer(ramCaddr0));
            ramCout0 <= ramCreg0;
            if ramCwriteEnable0 = '1' then
                ramC(conv_integer(ramCaddr0)) := ramCdata0;
            end if;
        end if;
    end process;
                 
    ramC_port1 : process(clock) begin
        if rising_edge(clock) then
            ramCreg1 <= ramC(conv_integer(ramCaddr1));
            ramCout1 <= ramCreg1;
            if ramCwriteEnable1 = '1' then
                ramC(conv_integer(ramCaddr1)) := ramCdata1;
            end if;
        end if;
    end process;

end Behavioral;
