module StreamNCapture #(
    NSTREAM = 16,
    NCAPTURE = 12) (
    //System clock and reset_n
    input  logic                        sys_arstn,
    input  logic                        sys_clk,
    // Parameter
    input  logic  [31:0]                size,
    input  logic  [1:0]                 op_mode,
    input  logic                        go,
    // Read Port
    input  logic                        r_valid,
    input  logic  [127:0]               r_data,
    output logic                    	r_req,  
    // Write Port 
    output logic                    	w_valid,
    input  logic                        w_accept,
    output logic [127:0]            	w_data,
    output logic                    	w_req,
    // Status 	
    output logic                    	finish,
    output logic                    	pass,
    // VIO interface	
    output logic [NSTREAM-1:0]      	stream,
    input  logic [NCAPTURE-1:0]         capture);
    
    // testpattern decoding
    logic [NSTREAM-1:0] 	stream_vector;
    logic [NCAPTURE-1:0]	expected_vector;
    logic [NCAPTURE-1:0]	mask_vector;
    assign stream_vector = r_data [NSTREAM-1:0];
    assign expected_vector = r_data [(NCAPTURE + NSTREAM-1):NSTREAM];
    assign mask_vector = r_data [(2*(NCAPTURE) + NSTREAM-1):NCAPTURE + NSTREAM];
    // main state machine
    enum logic [1:0] { IDLE=2'b00, MODE_A=2'b01, MODE_B=2'b10, TEST_MODE=2'b11 } state, next_state;
    logic [31:0] read_count;
    logic [31:0] write_count;

    always_ff @( posedge sys_clk, negedge sys_arstn ) begin : state_update
        if (!sys_arstn) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin : next_state_logic
        case (state)
            IDLE: begin
                if (go) begin
                    case (op_mode)
                        2'b00: next_state = MODE_A;
                        2'b01: next_state = MODE_B;
                        2'b10: next_state = TEST_MODE;
                        2'b11: next_state = TEST_MODE;
                    endcase
                end else next_state = IDLE;
            end

            MODE_A: begin
                if (write_count < size) begin
                    next_state = MODE_A;
                end else begin
                    next_state = IDLE;
                end
            end

            MODE_B: begin
                if (write_count < size) begin
                    next_state = MODE_B;
                end else begin
                    next_state = IDLE;
                end
            end

            TEST_MODE: begin
                if (write_count < size) begin
                    next_state = TEST_MODE;
                end else begin
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    always_comb begin : read_request
        case (state)
            IDLE:       r_req <= 0;
            MODE_A:     r_req <= (read_count < size) ? 1 : 0;
            MODE_B:     r_req <= (read_count < size) ? 1 : 0;
            TEST_MODE:  r_req <= 0;
        endcase
    end

    always_ff @( posedge sys_clk ) begin : read_data
        case (state)
            IDLE: read_count <= 0;
            MODE_A: begin
                if (r_valid) begin
                    stream <= stream_vector;
					read_count <= read_count + 1;
                end
            end 
            MODE_B: begin
                if (r_valid) begin
                    stream <= stream_vector;
					read_count <= read_count + 1;
                end
            end 
			TEST_MODE: begin
				if (w_accept) begin
					stream <= read_count [NSTREAM-1:0];
					read_count <= read_count + 1;
				end
			end
        endcase
    end

// delaying test vector for 1 cycle to adjust with CAPTUREd data

    logic [NSTREAM-1:0]          stream_vector_delayed;
    logic [NCAPTURE-1:0]         expected_vector_delayed;
    logic [NCAPTURE-1:0]         mask_vector_delayed;

    always_ff @( posedge sys_clk ) begin : pipeline
        if (!sys_arstn) begin
            stream_vector_delayed   <= 0;
            expected_vector_delayed <= 0;  
            mask_vector_delayed <= 0;
        end else begin
            stream_vector_delayed <= stream_vector;
            expected_vector_delayed <= expected_vector;
            mask_vector_delayed <= mask_vector;
        end
    end

    always_ff @( posedge sys_clk ) begin : write_request
        case (state)
            IDLE:       w_req <= 0;
            MODE_A:     w_req <= ((write_count < size)&& r_req) ? 1 : 0;
            MODE_B:     w_req <= ((write_count < size)&& r_req) ? 1 : 0;
            TEST_MODE:  w_req <= (write_count < size) ? 1 : 0;
        endcase
    end

    always_ff @( posedge sys_clk ) begin : write_data
        case (state)
            IDLE: begin
                w_data <= 0;
                w_valid <= 0;
                write_count <= 0;
            end 
            MODE_A: begin
                if (w_accept) begin
                    if (write_count < size) begin
                        w_data <= capture;
                        w_valid <= 1;
                        write_count <= write_count + 1;    
                    end else begin
                        w_data <= 0;
                        w_valid <= 0;
                        write_count <= 0;
                    end    
                end 
            end
            MODE_B: begin
                if (w_accept) begin
                    if (write_count < size) begin
                        w_data <= mask_vector_delayed & (expected_vector_delayed ^ capture);
                        w_valid <= 1;
                        write_count <= write_count + 1;    
                    end else begin
                        w_data <= 0;
                        w_valid <= 0;
                        write_count <= 0;
                    end    
                end 
            end
            TEST_MODE: begin
                if (w_accept) begin
                    if (write_count < size) begin
                        w_data <= capture;
                        w_valid <= 1;
                        write_count <= write_count + 1;    
                    end else begin
                        w_data <= 0;
                        w_valid <= 0;
                        write_count <= 0;
                    end    
                end 
            end

        endcase
    end

    always_ff @( posedge sys_clk ) begin : finish_logic
        if (state == IDLE) finish <= 0; 
        else if (state == MODE_A || state == MODE_B || state == TEST_MODE) begin
            finish <= (write_count < size) ? 0 : 1;
        end
    end

    //// pass/fail
    logic [31:0] error_acc;
    always_ff @( posedge sys_clk ) begin : error_accomulator
        if (state == MODE_B) begin
            error_acc <= (w_data[NCAPTURE-1:0] != {NCAPTURE{1'b0}}) ? 1 : 0;
        end else begin
            error_acc <= 0;
        end   
    end

    always_ff @( posedge sys_clk ) begin : pass_logic
        if (state == MODE_B) begin
            pass <= ((write_count == size)&&(error_acc == 0)) ? 1 : 0;
        end else begin
            pass <= 0;
        end   
    end
endmodule