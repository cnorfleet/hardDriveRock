`define NUM_INPUTS   1   // number of tracks (and tone generators) used
`define NUM_OUTPUTS  1   // number of output channels used
`define PACKET_SIZE  24  // bits of data per track in each packet
`define FILTER_WIDTH 256 // 2^8 clock cycles between amplitude changes so good filter width

module testbench();
    logic clk, reset, cs, sck, sdi;
	 logic[`NUM_OUTPUTS-1:0] A, B, C, D;
    logic[(`PACKET_SIZE*`NUM_INPUTS)-1:0] packet;
    integer i;
	 
	 // low-pass filter of output signal in order to check that it's working right
	 logic lastOutputs[`FILTER_WIDTH];
	 int lowPassFilteredOutput;
	 assign lowPassFilteredOutput = lastOutputs.sum with (int'(item)); // don't need: "/ `FILTER_WIDTH";
	 // ^ note that we need to cast the output to an int before summing
	 // so that we don't just get a one-bit sum with a lot of overflowing
    
    // device under test
    top #(`NUM_INPUTS, `NUM_OUTPUTS) dut (clk, reset, cs, sck, sdi, A, B, C, D);
    
    // test case
    initial begin
			if(`NUM_INPUTS == 1)
				packet <= 24'h0114ff;
			else
				packet <= 96'h0114ff0217ff0114ff0217ff;
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
			if (i == `PACKET_SIZE*`NUM_INPUTS) cs = 1'b0;
			if (i<`PACKET_SIZE*`NUM_INPUTS) begin
			  #1; sdi = packet[(`PACKET_SIZE*`NUM_INPUTS)-1-i];
			  #1; sck = 1; #5; sck = 0;
			end
			i = i + 1;
			lastOutputs[(i % `FILTER_WIDTH)] = dut.oc[0].waveOut;
		end
	 end
    
endmodule
