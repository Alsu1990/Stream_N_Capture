`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/09/2021 10:38:50 PM
// Design Name: 
// Module Name: Pattern_Stream_N_Capture_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module Pattern_Stream_N_Capture_2V0_tb();
localparam SIZE = 32;   // i_size port width. max test vector length 2^^(SIZE).
localparam VECTOR_LENGTH = 20; // Testbench vector length
localparam NSTREAM = 12;
localparam NCAPTURE = 8;
/////////////////////////////////
reg                 i_rstn;
reg                 i_clk;
//  parameters
reg [SIZE-1:0]      i_size;
reg [1:0]           i_op_mode;
reg                 i_go;
// Read port
reg                 i_read_valid;
reg [127:0]         i_read_data;
wire                o_read_request;
// Write Port
wire                o_write_valid;
reg                 i_write_accept;
wire [127:0]        o_write_data;
wire                o_write_request;
// Status
wire                o_finish;
wire                o_pass;
// VIO interface
wire [NSTREAM-1:0]  o_stream;
wire [NCAPTURE-1:0]  i_capture;     
/////////////////////////////////////
Pattern_Stream_N_Capture_2V0 #(
    .SIZE(SIZE),
    .NSTREAM(NSTREAM),
    .NCAPTURE(NCAPTURE))
DUT(
    .i_clk(i_clk),
    .i_rstn(i_rstn),
    .i_size(i_size),
    .i_op_mode(i_op_mode),
    .i_go(i_go),
    .i_read_valid(i_read_valid),
    .i_read_data(i_read_data),
    .o_read_request(o_read_request),
    .o_write_valid(o_write_valid),
    .i_write_accept(i_write_accept),
    .o_write_data(o_write_data),
    .o_write_request(o_write_request),
    .o_finish(o_finish),
    .o_pass(o_pass),
    .o_stream(o_stream),
    .i_capture(i_capture)
    );

initial begin
    $dumpfile ("Stream_n_Capture_waveforms.vcd");
    $dumpvars(0,Pattern_Stream_N_Capture_2V0_tb);
end

//////////////////////////////////////
reg [127:0]  r_test_pattern [0:VECTOR_LENGTH-1] ;  // test pattern
reg [NSTREAM-1:0]  r_asic_test_chain [0:VECTOR_LENGTH-1]; // actual stream vector fetched by asic
reg [NSTREAM-1:0] r_stream_vector_cycle;  // stream to asic vector
reg [NCAPTURE-1:0] r_mask_vector_cycle; // mask vector for valid pattern compare
reg [NCAPTURE-1:0] r_expected_vector_cycle; // expected vector cycle


reg [NCAPTURE-1:0]  r_capture_vector [0:VECTOR_LENGTH-1] ; // capture from asic vector
integer i = 0, j = 0;

reg [127:0]  r_write_data_checker [0:VECTOR_LENGTH-1] ;  // dut error write data check
///////////////////////////////////////////////////////
// task for mode_A test 
task test_pattern_gen;
    begin
        // @(posedge i_clk) i_rstn = 0;
        for (i = 0;i < VECTOR_LENGTH ;i = i+1 ) begin
            r_mask_vector_cycle = $random;
            r_expected_vector_cycle = $random;
            r_stream_vector_cycle = $random;
            r_capture_vector[i] = r_expected_vector_cycle;  // best case scenario where captured data from ASIC equals to expected vector
            // r_capture_vector[i] = $random;  
            r_test_pattern[i] = {r_mask_vector_cycle, r_expected_vector_cycle, r_stream_vector_cycle};
            r_write_data_checker[i] = r_mask_vector_cycle & (r_capture_vector[i] ^ r_expected_vector_cycle); //mode b check lut
        end
        // @(posedge i_clk) i_rstn = 1;
        @(posedge i_clk) i_go = 1;      // start pulse
        @(posedge i_clk) i_go = 0;
    end
endtask

always #5 i_clk = ~i_clk;   //100 mhz clk
integer error_count = 0;
// USE_CASE1 - MODE A
initial begin
    //initial values
    i_read_valid = 0;
    i_clk = 0;
    i_rstn = 0;
    i_size = (VECTOR_LENGTH);    // test pattern length
    i_go = 0;
    i_op_mode = 2'b00;  // MODE_A
    @(posedge i_clk) i_rstn = 1;
    repeat(1) begin
        test_pattern_gen;   // generate first vector
        @(posedge o_finish);        
    end

    #100;
    i_op_mode = 2'b01;  // MODE_B

    repeat(1) begin
        test_pattern_gen;   // generate first vector
        @(posedge o_finish);        
    end

    #30;

    i_op_mode = 2'b10;  // TEST_MODE
    #100;
    @(posedge i_clk) i_rstn = 0;
    @(posedge i_clk) i_rstn = 1;
    #30;
    @(posedge i_clk) i_go = 1;      // start pulse
    @(posedge i_clk) i_go = 0;
    @(posedge o_finish) #100;

    if (error_count == 0) $display ("Simulation ended without errors");
    else $display (" %d Errors were found",error_count);
    $finish;
end








///////////////// read from memory process ///////////////////////
reg [31:0] read_count = 0;

always @(posedge i_clk) begin
    if (o_read_request) begin
        if (read_count < VECTOR_LENGTH) begin
            read_count <= read_count + 1;
            i_read_valid <= 1'b1;
            i_read_data <= r_test_pattern[read_count];
            // $display("read_count= %d, r_test_pattern = %h, time = %t",read_count,r_test_pattern[read_count],$time);  
        end else begin
            i_read_valid <= 1'b0;
            read_count <= 0;
            i_read_data <= 0;
        end
    end
end
///////////////////////////////////////////////////////////////////

/////////////////// write to memory ///////////////////////////////
integer write_count;

reg [127:0]  r_write_mem [0:VECTOR_LENGTH-1];

always @(posedge i_clk ) begin
    if (!i_rstn) begin
        write_count <= 0;
        // for (j = 0;j < VECTOR_LENGTH;j = j + 1 ) begin
        //     r_write_mem[j] <= 0;
        // end
    end 
    else begin
            if (o_write_valid) begin   
                    r_write_mem[write_count] <= o_write_data;
                    write_count <= write_count + 1; 
                    // $display("write_count = %d, o_write_data = %h, time = %t",write_count,o_write_data,$time);    
            end            
    end      
end

always @(posedge i_clk ) begin
   if (o_write_request)  i_write_accept <= 1'b1;
   else i_write_accept <= 1'b0;
end
/////////////////////////////////////////////////////////////

///////////////// fsm for asic simulation ///////////////////
localparam IDLE = 1'b0, SHIFTING = 2'b1;
reg  state, next_state;
integer asic_state_cnt = 0;
///////////////// state update block ////////////////////////
always @(posedge i_clk) begin
    if(!i_rstn)
        state <= IDLE;
    else
        state <= next_state;
end
//////////////// next state logic ////////////////////////////
always @(state, i_read_valid, asic_state_cnt, i_write_accept ) begin
    case (state)
        IDLE:   begin
            if (i_read_valid || ((i_op_mode == 2) && i_write_accept)) next_state <= SHIFTING;
            else next_state <= IDLE;
        end
        SHIFTING: begin
            if (asic_state_cnt < VECTOR_LENGTH - 1) next_state <= SHIFTING;
            else next_state <= IDLE;
        end

        default: next_state <= IDLE; 
    endcase   
end
//////////////// output logic ////////////////////////////

//////////////////////////////////////////////////////////
always @(posedge i_clk ) begin
    case (state)
        IDLE: begin
            asic_state_cnt <= 0;
        end
        SHIFTING: begin
            if (asic_state_cnt < VECTOR_LENGTH) begin
                asic_state_cnt <= asic_state_cnt + 1;
                r_asic_test_chain[asic_state_cnt] <= o_stream;
            end
            else begin 
                asic_state_cnt <= 0;
            end
        end
    endcase    
end

assign i_capture = state ? r_capture_vector[asic_state_cnt] : {(NCAPTURE){1'bZ}};

// error checker.
// compairs test vector with data streamed into the asic
reg [127:0] n_stream_mask = {(NSTREAM){1'b1}};

always @(*) begin
    @(posedge o_finish) begin
        if (i_op_mode == 2'b00) begin   // MODE A ERROR CHECKER
            for (i = 0;i < VECTOR_LENGTH ;i = i+1 ) begin   // streamed vector check
                if (r_asic_test_chain[i]   != (r_test_pattern[i] & n_stream_mask)) begin    // masking the relevant test pattern data [NSTREAM-1:0] bits
                    error_count = error_count + 1;
                    $display("Error in MODE A STREAMED_DATA[%d]. Expected value %h. Actual data %h", i, r_test_pattern[i] & n_stream_mask, r_asic_test_chain[i]);
                end
            end 
            #0.1;
            for (i = 0;i < VECTOR_LENGTH ;i = i+1 ) begin   // captured vector check
                if (r_write_mem[i]  != r_capture_vector[i]) begin
                    error_count = error_count + 1;
                    $display("Error in MODE A WRITE_DATA[%d]. Expected value %h. Actual data %h", i, r_capture_vector[i], r_write_mem[i] );
                end
            end
        end 
        else if (i_op_mode == 2'b01) begin
            for (i = 0;i < VECTOR_LENGTH ;i = i+1 ) begin
                if (r_asic_test_chain[i]   != (r_test_pattern[i] & n_stream_mask)) begin    // masking the relevant test pattern data [NSTREAM-1:0] bits
                    error_count = error_count + 1;
                    $display("Error in MODE B STREAMED_DATA[%d]. Expected value %h. Actual data %h", i, r_test_pattern[i] & n_stream_mask, r_asic_test_chain[i]);
                end
            end
            #0.1;
            for (i = 0;i < VECTOR_LENGTH ;i = i+1 ) begin
                if (r_write_mem[i]  != r_write_data_checker[i]) begin
                    error_count = error_count + 1;
                    $display("Error in MODE B WRITE_DATA[%d]. Expected value %h. Actual data %h", i, r_write_data_checker[i],r_write_mem[i]);
                end
            end
        end
    end  
end



endmodule