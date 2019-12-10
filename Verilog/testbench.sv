`define NUM_TRACKS 1   // number of tracks (and tone generators) used
`define PACKET_SIZE 24 // bits of data per track in each packet

module testbench();
    logic clk, reset, cs, sck, sdi;
	 logic[`NUM_TRACKS-1:0] A, B, C, D;
    logic[(`PACKET_SIZE*`NUM_TRACKS)-1:0] packet;
    integer i;
    
    // device under test
    top dut(clk, reset, cs, sck, sdi, A, B, C, D);
    
    // test case
    initial begin
			if(`NUM_TRACKS == 1)
				packet <= 24'h0114ff;
			else
				packet <= 48'h0114ff0217ff;
			reset <= 1'b1; #22; reset <= 1'b0;
    end
    
    // generate clock and load signals
    initial 
        forever begin
            clk = 1'b0; #5;
            clk = 1'b1; #5;
        end
        
    initial begin
      i = 0; sck = 0;
      cs<=1'b1; #1; cs <= 1'b0; #23; cs <= 1'b1;
    end 
    
    // shift in test vectors over SPI
    always @(posedge clk) begin
		if(~reset) begin
			if (i == 24*`NUM_TRACKS) cs = 1'b0;
			if (i<24*`NUM_TRACKS) begin
			  #1; sdi = packet[(24*`NUM_TRACKS)-1-i];
			  #1; sck = 1; #5; sck = 0;
			end
			i = i + 1;
		end
	 end
    
endmodule
