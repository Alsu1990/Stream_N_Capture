`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/02/2021 12:15:55 PM
// Design Name: 
// Module Name: Pattern_Stream_N_Capture_2V0
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


module Pattern_Stream_N_Capture_2V0 #(
    SIZE = 32,
    NSTREAM = 16,
    NCAPTURE = 12
    )(
    //System clock and reset_n
    input                       i_clk,          // 100 MHz clock
    input                       i_rstn,         // async reset active low
    // Parameters           
    input [SIZE-1:0]            i_size,
    input [1:0]                 i_op_mode,      // operation mode. 00 - Mode A. 01 - Mode B, 10/11 - Test Mode
    input                       i_go,           // start bit
    // Read Port        
    input                       i_read_valid,
    input [127:0]               i_read_data,
    output  reg                 o_read_request,
    // Write Port       
    output  reg                 o_write_valid,
    input                       i_write_accept,
    output  reg [127:0]         o_write_data,
    output  reg                 o_write_request,
    // Status       
    output  reg                 o_finish,
    output  reg                 o_pass,         // if '1' test pass, if '0' test fail
    // VIO interface
    output  reg [NSTREAM-1:0]   o_stream,
    input   [NCAPTURE-1:0]      i_capture);

    ////////////////// test_vector assigns///////////////////
    wire [NSTREAM-1:0]          w_stream_vector;
    wire [NCAPTURE-1:0]         w_expected_vector;
    wire [NCAPTURE-1:0]         w_mask_vector;
    assign w_stream_vector = i_read_data [NSTREAM-1:0];
    assign w_expected_vector = i_read_data [(NCAPTURE + NSTREAM)-1:NSTREAM];
    assign w_mask_vector = i_read_data [(2*NCAPTURE + NSTREAM)-1:(NCAPTURE + NSTREAM)];
    ///////////////// FSM parameters and registers ///////
    localparam  IDLE = 3'b00, MODE_A = 3'b01, MODE_B = 3'b10, TEST_MODE = 3'b11;    // main FSM states
    reg [1:0]   state, next_state;
    reg [SIZE-1:0] r_read_mem_cnt; // read from memory "READ PORT" counter
    reg [SIZE-1:0] r_write_mem_cnt; // write to memory "WRITE PORT" counter
    ///////////////// state update block /////////////////
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn)
            state <= IDLE;
        else
            state <= next_state;
    end
    ///////////////// next state logic /////////////////
    always @(state, i_go, o_finish, r_read_mem_cnt, r_write_mem_cnt, i_op_mode,i_size) begin
        case (state)
            IDLE:   begin
                if (i_go) begin
                    case (i_op_mode)
                        2'b00: next_state <= MODE_A;
                        2'b01: next_state <= MODE_B;
                        2'b10: next_state <= TEST_MODE;
                        2'b11: next_state <= TEST_MODE;
                    endcase
                end else next_state <= IDLE;
            end

            MODE_A: begin                                       // Stream and Capture mode
                if (r_write_mem_cnt < i_size) begin
                    next_state <= MODE_A;
                end else begin
                    next_state <= IDLE;
                end   
            end 

            MODE_B: begin                                       // Patter check mode
                if (r_write_mem_cnt < i_size) begin
                    next_state <= MODE_B;
                end else begin
                    next_state <= IDLE;
                end   
            end 

            TEST_MODE: begin                                       // Patter check mode
                if (r_write_mem_cnt < i_size) begin
                    next_state <= TEST_MODE;
                end else begin
                    next_state <= IDLE;
                end   
            end 

            default: next_state <= IDLE;
        endcase 
    end

////////////////////////////// output logic ////////////////////////////////////////
///////////// read from memory //////////////////////////////////////////

    always @(posedge i_clk ) begin
        case (state)
            IDLE: o_read_request <= 0;
            MODE_A: begin
                // request to read from memmory. "&& next state" to avoid additional request pulse glitch between state transitions while counter becomes zero 
                if ((r_read_mem_cnt < i_size - 1) && next_state == MODE_A) o_read_request <= 1; 
                else o_read_request <= 0;
            end
            MODE_B: begin
                if ((r_read_mem_cnt < i_size - 1) && next_state == MODE_B) o_read_request <= 1;
                else o_read_request <= 0;
            end
            TEST_MODE: o_read_request <= 0;
            default: o_read_request <= 0;
        endcase
    end


////////////////////////////////////////////////////////////////////////
    always @(posedge i_clk ) begin
        if (state == IDLE) begin
            r_read_mem_cnt <= 0;
        end else if (state == MODE_A || state == MODE_B) begin
            if(i_read_valid) begin
                r_read_mem_cnt <= r_read_mem_cnt + 1'b1;
                o_stream <= w_stream_vector;   
            end else begin
                r_read_mem_cnt <= 0;
            end 
        end else if (state == TEST_MODE) begin
            if(i_write_accept) begin                    // start streaming when write port ready
                r_read_mem_cnt <= r_read_mem_cnt + 1'b1;
                o_stream <= r_read_mem_cnt[NSTREAM-1:0];   
            end
        end   
    end

 ////// pipelining w_stream_vector/w_expected_vector/w_mask_vector to allign with ASIC input/output ( 1 clock_cycle)
///////// MODE_B/////////////
    reg [NSTREAM-1:0]          r_stream_vector;
    reg [NCAPTURE-1:0]         r_expected_vector;
    reg [NCAPTURE-1:0]         r_mask_vector;

    always @(posedge i_clk ) begin
        r_stream_vector <= w_stream_vector;
        r_expected_vector <= w_expected_vector;
        r_mask_vector <= w_mask_vector;
    end
////////////// write to memory ////////////////////////

    always @(posedge i_clk ) begin
        if (state == IDLE) begin
            o_write_request <= 0;
        end else if (state == MODE_A || state == MODE_B) begin
            if((r_write_mem_cnt < i_size - 1) && (o_read_request)) begin   // write request comes after read request
            // if((r_write_mem_cnt < i_size - 1)) begin   // write request comes after read request
                o_write_request <= 1;
            end else begin
                o_write_request <= 0;
            end             
        end else if (state == TEST_MODE) begin
            if(r_write_mem_cnt < i_size - 1) begin  
                o_write_request <= 1;  
            end else begin
                o_write_request <= 0;
            end             
        end
    end

/////////////////////////////////////////////
    always @(posedge i_clk) begin
        case (state)
            IDLE: begin
                o_write_data <= 0;
                o_write_valid <= 0;
                r_write_mem_cnt <= 0; 
            end
            MODE_A: begin
                if (i_write_accept) begin
                    if (r_write_mem_cnt < i_size) begin
                        o_write_data <= i_capture;
                        o_write_valid <= 1;
                        r_write_mem_cnt <= r_write_mem_cnt + 1;   
                    end else begin
                        r_write_mem_cnt <= 0;
                        o_write_data <= 0;
                        o_write_valid <= 0;  
                    end
                end
            end
            MODE_B: begin
                if (i_write_accept) begin
                    if (r_write_mem_cnt < i_size) begin
                        o_write_data <= r_mask_vector & (r_expected_vector ^ i_capture);       // check actual vector with expected one
                        o_write_valid <= 1;
                        r_write_mem_cnt <= r_write_mem_cnt + 1;
                    end else begin
                        r_write_mem_cnt <= 0;
                        o_write_data <= 0;
                        o_write_valid <= 0;  
                    end 
                end 
            end
            TEST_MODE: begin
                if (i_write_accept) begin
                    if (r_write_mem_cnt < i_size) begin
                        o_write_data <= i_capture;
                        o_write_valid <= 1;
                        r_write_mem_cnt <= r_write_mem_cnt + 1;   
                    end else begin
                        r_write_mem_cnt <= 0;
                        o_write_data <= 0;
                        o_write_valid <= 0;  
                    end
                end
            end
            default: begin
                o_write_data <= 0;
                o_write_valid <= 0;
                r_write_mem_cnt <= 0; 
            end
        endcase
    end


////////////// finish logic ////////////////////////////
    always @(posedge i_clk ) begin
        if (state == IDLE) begin
                o_finish <= 0;
        end else if (state == MODE_A || state == MODE_B || state == TEST_MODE) begin
            if ((r_write_mem_cnt < i_size)) begin  
                o_finish <= 0;
            end else begin
                o_finish <= 1;
            end          
        end    
    end

////////////// pass logic ////////////////////////////////
reg[SIZE-1:0] error_acc;
   always @(posedge i_clk ) begin
        if (state == MODE_B) begin
            if (| o_write_data[NCAPTURE-1:0]) error_acc <= error_acc + 1;
        end else error_acc <= 0;
    end

    always @(posedge i_clk ) begin
        if (state == IDLE) begin
                o_pass <= 0;
        end else if (state == MODE_B) begin
            if ((r_write_mem_cnt == i_size) && (!error_acc)) begin  
                o_pass <= 1;
            end else begin
                o_pass <= 0;
            end          
        end    
    end
/////////////////////////////////////////////////////////////////////////////////////
endmodule

