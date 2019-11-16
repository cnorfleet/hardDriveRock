module top(input  logic clk, reset,
			  input  logic chipSelect, sck, sdi,
			  output logic carrierOut);
	// Erik Meike and Caleb Norfleet
	// FPGA stuff for uPs final project
	
	logic [15:0] tuneWord;   // frequency of note signal
	logic        sign;       // note signal sign
	logic [7:0]  amplitude;  // note signal amplitude
	logic [7:0]  volume;     // unsigned volume of output
	logic [7:0]  currentVol; // volume only updated after every 2^8 clock cycles
	logic [7:0]  magnitude;  // amplitude of wave after multiplying with volume
	logic        carrier;    // output signal.  PWM at 40MHz to achieve amplitude at 156.25 kHz
	
	// main modules
	spi s(chipSelect, sck, sdi, tuneWord, volume);
	waveGen wg(clk, reset, wgEn, tuneWord, sign, amplitude);
	logic [15:0] mult;
	assign mult = ({8'b0, amplitude} * {8'b0, currentVol});
	assign magnitude = (mult[7] & ~&mult[15:8]) ? (mult[15:8] + 8'b1) : (mult[15:8]);
	// ^ note: rounding with saturation
	pwmGen pg(clk, reset, waveCounter, magnitude, carrier);
	
	assign carrierOut = carrier; // TODO: remove this debug signal
	// TODO: need to generate FET driver signals based on sign and carrier
	
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
			  output logic [15:0] tuneWord,
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
			readData <= {readData[22:0], sdi};
			dataCount = dataCount + 5'b1;
			if(dataCount == 5'd24) begin
				tuneWord   <= readData[23:8];
				volume <= readData[7:0];
				dataCount = 5'b0;
			end
		end
		else dataCount <= 5'b0;
	end
endmodule

module waveGen(input  logic clk, reset, wgEn,
					input  logic[15:0] tuneWord,
					output logic       sign,
					output logic[7:0]  amplitude);
	// Caleb Norfleet, cnorfleet@hmc.edu, 11/14/19
	// generates sinusoid based on tuneWord
	
	logic[15:0] phaseAcc;             // phase accumulator
	logic[7:0]  LUTsine[(2**10-1):0]; // look up table
	
	logic nextSign;
	logic[11:0] nextPhase;
	assign nextSign = phaseAcc[15]; // neg in second half
	assign nextPhase = (phaseAcc[14]) ? (12'h000 - phaseAcc[13:4]) : (phaseAcc[13:4]);
	// ^ note that phase is adjusted since we're using a 1/4 phase LUT
	
	always_ff @(posedge clk) begin
		if(reset) begin
			phaseAcc  <= 16'b0;
			amplitude <= 8'b0;
		end
		else if(wgEn) begin
			phaseAcc  <= phaseAcc + tuneWord;
			amplitude <= LUTsine[nextPhase];
			sign      <= nextSign;
		end
	end
	
	initial begin
		$readmemb("LUTsine.txt", LUTsine);
	end
	
endmodule

module pwmGen(input  logic      clk, reset,
				  input  logic[7:0] waveCounter,
				  input  logic[7:0] magnitude,
				  output logic      carrier);
	// Caleb Norfleet, cnorfleet@hmc.edu, 11/15/19
	// modulates carrier signal based on sine wave
	
	always_ff @(posedge clk) begin
		carrier <= (~reset & (waveCounter < magnitude));
		// PWM carrier by magnitude
	end
endmodule
