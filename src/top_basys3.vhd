--+----------------------------------------------------------------------------
--|
--| NAMING CONVENSIONS :
--|
--|    xb_<port name>           = off-chip bidirectional port ( _pads file )
--|    xi_<port name>           = off-chip input port         ( _pads file )
--|    xo_<port name>           = off-chip output port        ( _pads file )
--|    b_<port name>            = on-chip bidirectional port
--|    i_<port name>            = on-chip input port
--|    o_<port name>            = on-chip output port
--|    c_<signal name>          = combinatorial signal
--|    f_<signal name>          = synchronous signal
--|    ff_<signal name>         = pipeline stage (ff_, fff_, etc.)
--|    <signal name>_n          = active low signal
--|    w_<signal name>          = top level wiring signal
--|    g_<generic name>         = generic
--|    k_<constant name>        = constant
--|    v_<variable name>        = variable
--|    sm_<state machine type>  = state machine type definition
--|    s_<signal name>          = state name
--|
--+----------------------------------------------------------------------------
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;


entity top_basys3 is
    port(
        -- inputs
        clk     :   in std_logic; -- native 100MHz FPGA clock
        sw      :   in std_logic_vector(7 downto 0); -- operands and opcode
        btnU    :   in std_logic; -- reset
        btnC    :   in std_logic; -- fsm cycle
        btnL    :   in std_logic; -- clock divider button
        -- outputs
        led :   out std_logic_vector(15 downto 0);
        -- 7-segment display segments (active-low cathodes)
        seg :   out std_logic_vector(6 downto 0);
        -- 7-segment display active-low enables (anodes)
        an  :   out std_logic_vector(3 downto 0)
    );
end top_basys3;

architecture top_basys3_arch of top_basys3 is 
  
	-- declare components and signals

    -- signal declarations
	signal w_o_cycle : STD_LOGIC_VECTOR (3 downto 0);
	signal w_clk : std_logic;
    signal w_clk_reset : std_logic;
    
    signal reg_A_val : STD_LOGIC_VECTOR (7 downto 0);
    signal reg_B_val : STD_LOGIC_VECTOR (7 downto 0);
    signal reg_sw : STD_LOGIC_VECTOR (7 downto 0);
    
    signal w_o_result   : STD_LOGIC_VECTOR (7 downto 0);
    signal w_hex    :   STD_LOGIC_VECTOR (3 downto 0);
    
    --TDM4
    signal w_o_sign : std_logic;
    signal w_i_bin  : STD_LOGIC_VECTOR (7 downto 0); --**
    signal w_o_hund : STD_LOGIC_VECTOR (3 downto 0);
    signal w_o_tens : STD_LOGIC_VECTOR (3 downto 0);
    signal w_o_ones : STD_LOGIC_VECTOR (3 downto 0);
    signal w_an : STD_LOGIC_VECTOR (3 downto 0);
    
    --tdm mux
    signal w_o_sign_mux : STD_LOGIC_VECTOR(6 downto 0);
    
    --twos comp mux
    signal w_i_bin_mux  : STD_LOGIC_VECTOR(7 downto 0);
    
    --sevenseg mux
    signal w_seg_mux    :   STD_LOGIC_VECTOR(6 downto 0);
    signal w_seg    :   STD_LOGIC_VECTOR(6 downto 0);
    
    --clearDisplay mux
    signal w_clearDisplay   :   STD_LOGIC_VECTOR (3 downto 0);
    
    signal w_i_adv : std_logic;
    
  
    -- component declarations
component button_debounce is
	Port(	clk: in  STD_LOGIC;
			reset : in  STD_LOGIC;
			button: in STD_LOGIC;
			action: out STD_LOGIC);
end component;

component controller_fsm is
    port ( i_reset : in STD_LOGIC;
           i_adv : in STD_LOGIC;
           o_cycle : out STD_LOGIC_VECTOR (3 downto 0));
end component controller_fsm;



component ALU is
    Port ( i_A : in STD_LOGIC_VECTOR (7 downto 0);
           i_B : in STD_LOGIC_VECTOR (7 downto 0);
           i_op : in STD_LOGIC_VECTOR (2 downto 0); --i op is ALUcontrol
           o_result : out STD_LOGIC_VECTOR (7 downto 0);
           o_flags : out STD_LOGIC_VECTOR (3 downto 0));
end component ALU;



component TDM4 is
	generic ( constant k_WIDTH : natural  := 4); -- bits in input and output
    Port ( i_clk		: in  STD_LOGIC;
           i_reset		: in  STD_LOGIC; -- asynchronous
           i_D3 		: in  STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
		   i_D2 		: in  STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
		   i_D1 		: in  STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
		   i_D0 		: in  STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
		   o_data		: out STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
		   o_sel		: out STD_LOGIC_VECTOR (3 downto 0)	-- selected data line (one-cold)
	);
end component TDM4;
  
  
  
component sevenseg_decoder is
    Port ( i_Hex : in STD_LOGIC_VECTOR (3 downto 0);
           o_seg_n : out STD_LOGIC_VECTOR (6 downto 0));
end component sevenseg_decoder;




component twos_comp is
    port (
        i_bin: in std_logic_vector(7 downto 0);
        o_sign: out std_logic;
        o_hund: out std_logic_vector(3 downto 0);
        o_tens: out std_logic_vector(3 downto 0);
        o_ones: out std_logic_vector(3 downto 0)
    );
end component twos_comp;




component clock_divider is
	generic ( constant k_DIV : natural := 2	); -- How many clk cycles until slow clock toggles
											   -- Effectively, you divide the clk double this 
											   -- number (e.g., k_DIV := 2 --> clock divider of 4)
	port ( 	i_clk    : in std_logic;
			i_reset  : in std_logic;		   -- asynchronous
			o_clk    : out std_logic		   -- divided (slow) clock
	);
end component clock_divider;



begin
	-- PORT MAPS ----------------------------------------
button_debounce_inst: button_debounce
   	port map (	
   	    clk => clk,
		reset => btnU,
		button => btnC,
		action => w_i_adv
);
        
controller_fsm_inst : controller_fsm
    port map (
        i_reset => btnU,
        i_adv => w_i_adv,
        o_cycle => w_o_cycle
);
	
ALU_inst : ALU
    port map (
        i_A =>  reg_A_val,
        i_B =>  reg_B_val, 
        i_op => sw(2 downto 0),
        o_result => w_o_result,
        o_flags => led(15 downto 12)
);

    

TDM4_inst :   TDM4
    port map (
        i_clk =>  w_clk,
        i_reset => btnU,
        i_D3 => "0000", --hard code to nothing (ignore it)
        i_D2 => w_o_hund,
        i_D1 => w_o_tens,
        i_D0 => w_o_ones,
        o_data => w_hex,
        o_sel => w_an
);
 

seven_seg_inst :   sevenseg_decoder
    port map (
        i_Hex =>  w_hex,
        o_seg_n => w_seg
); 

twos_comp_inst :   twos_comp
    port map (
        i_bin =>  w_i_bin_mux,
        o_sign => w_o_sign,
        o_hund => w_o_hund,
        o_tens => w_o_tens,
        o_ones => w_o_ones
);



	-- CONCURRENT STATEMENTS ----------------------------
clock_divider_inst : clock_divider
    generic map ( k_DIV => 12500 ) -- 1 Hz clock from 100 MHz
    port map (
        i_clk => clk,
        i_reset  => btnL,	   -- asynchronous
        o_clk   => w_clk
);

--invisible mux
w_o_sign_mux  <=  "1111111" when (w_o_sign = '0') else
                  "0111111" when (w_o_sign = '1');

--twos comp
w_i_bin_mux   <=  reg_A_val when (w_o_cycle = "0010") else
                  reg_B_val when (w_o_cycle = "0100") else
                  w_o_result when (w_o_cycle = "1000") else
                  "00000000"; --8 bits
                  
--result mux for seven seg
w_seg_mux   <=  w_o_sign_mux when (w_an = "0111") else --passes the sign seven seg display val                   
                w_seg;              
                
seg <= w_seg_mux;         
                
                  
--clearDisplay mux        
w_clearDisplay  <= "1111" when (w_o_cycle = "0001") else
                   w_an; -- clear display state
an <= w_clearDisplay;

--set switches/connect
reg_sw <= sw;

--leds to cycle
--output <= wire
led(3 downto 0) <= w_o_cycle;



--PROCESS
process (w_o_cycle(1))
    begin
        if btnU = '1' then -- this is i_reset
            reg_A_val <= "00000000";
        elsif rising_edge(w_o_cycle(1)) then
            reg_A_val <= sw;
        end if;
    end process;

process (w_o_cycle(2))
    begin
        if btnU = '1' then
            reg_B_val <= "00000000";
        elsif rising_edge(w_o_cycle(2)) then
            reg_B_val <= sw;
        end if;
    end process;
    
	
end top_basys3_arch;
