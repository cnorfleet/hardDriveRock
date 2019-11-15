module top(input  logic clk, reset,
			  input  logic chipSelect, sck, sdi);
	
	logic[11:0] freq;   // frequency of note signal
	logic[15:0] wave;   // note signal
	logic[7:0]  volume; // volume of output.  Used with PWM of carrier signal at 125 kHz
	logic[15:0] mixed;  // carrier signal
	
	spi s(chipSelect, sck, sdi, freq, volume);
	
endmodule

module spi(input  logic chipSelect,
			  input  logic sck, 
			  input  logic sdi,
			  output logic [11:0] freq
			  output logic [7:0]  volume);
	// Caleb Norfleet, cnorfleet@hmc.edu, 11/14/19
	// Accepts frequency and volume input over SPI from ATSAM
	// Internal freq and volume only updated after full packet recieved
	
	logic[4:0]  dataCount;
	logic[23:0] readData;
	
	// assert chipSelect
	// shift in frequency in two bytes
	// shift in volume in one byte
	// deassert chipSelect or just repeat
	always_ff @(posedge sck) begin
		if(chipSelect) begin
			readData <= {readData[22:0], sdi}
			dataCount = dataCount + 5'b1;
			if(dataCount = 5'd24) begin
				freq   <= readData[19:8];
				volume <= readData[7:0];
				dataCount = 5'b0;
			end
		end
		else dataCount <= 5'b0;
	end
endmodule
