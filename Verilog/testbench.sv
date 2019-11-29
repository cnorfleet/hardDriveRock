module testbench();
    logic clk, reset, cs, sck, sdi;
	 logic A, B, C, D;
    logic [23:0] packet;
    logic [31:0] i;
    
    // device under test
    top dut(clk, reset, cs, sck, sdi, A, B, C, D);
    
    // test case
    initial begin
        packet <= 24'h0114ff;
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
    
    // shift in test vectors, wait until done, and shift out result
    always @(posedge clk) begin
		if(~reset) begin
			if (i == 24) cs = 1'b0;
			if (i<24) begin
			  #1; sdi = packet[23-i];
			  #1; sck = 1; #5; sck = 0;
			end //else if (i == 1000) begin
//            if (cyphertext == expected)
//                $display("Testbench ran successfully");
//            else $display("Error: cyphertext = %h, expected %h",
//                cyphertext, expected);
				//$stop();
			//end
			i = i + 1;
		 end
	 end
    
endmodule
