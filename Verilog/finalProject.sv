module top(input  logic clk, reset,
			  input  logic chipSelect, sck, sdi
			  output logic carrier);
	// Erik Meike and Caleb Norfleet
	// FPGA stuff for uPs final project
	
	logic [11:0] freq;       // frequency of note signal
	logic [7:0]  wave;       // note signal. signed number
	logic [7:0]  volume;     // unsigned volume of output
	logic [7:0]  currentVol; // volume only updated after every 2^8 clock cycles
	logic [7:0]  amplitude;  // amplitude of wave after multiplying with volume
	//logic        carrier;    // output signal.  PWM at 40MHz to achieve amplitude at 156.25 kHz
	
	// main modules
	spi         s(chipSelect, sck, sdi, freq, volume);
	waveGen    wg(clk, reset, wgEn, freq, wave);
	volumeMult vm(wave, volume, amplitude);
	
	// control signals
	logic[7:0] waveCounter;
	always_ff @(posedge clk) begin
		if(reset)  waveCounter <= 8'b0;
		else begin
			waveCounter <= waveCounter + 8'b1;
			if(wgEn) currentVol <= volume;
		end
	end
	
	logic wgEn; // wave gen runs at 156.25 kHz = 40MHz / 256 (aka 2^8)
	assign wgEn = (waveCounter == 8'b0);
	
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
	// shift in frequency in two bytes (MSB first)
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

module waveGen(input  logic clk, reset, wgEn,
					input  logic[11:0] freq,
					output logic[7:0]  wave)
	// Caleb Norfleet, cnorfleet@hmc.edu, 11/14/19
	// generates sinusoid at frequency (outputs signed number)
	
	logic[11:0] tuneWord;
	logic[15:0] phaseAcc;        // phase accumulator
	logic[7:0]  LUTcos[65535:0]; // look up table
	
	always_ff @(posedge clk) begin
		if(reset)     phaseAcc <= 16'b0;
		else if(wgEn) phaseAcc <= phaseAcc + {4'b0,tuneWord};
	end
	
	initial begin
		$readmemb("LUTcos.txt", LUTcos);
	end
	
endmodule
