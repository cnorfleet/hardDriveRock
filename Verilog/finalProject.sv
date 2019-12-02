module top(input  logic clk, reset,
			  input  logic chipSelect, sck, sdi,
			  output logic A, B, C, D);
	// Erik Meike and Caleb Norfleet
	// FPGA stuff for uPs final project
	
	logic [15:0] tuneWord;   // frequency of note signal
	logic        sign;       // note signal sign
	logic [7:0]  amplitude;  // note signal amplitude
	logic [7:0]  volume;     // unsigned volume of output
	logic [7:0]  currentVol; // volume only updated after every 2^8 clock cycles
	logic [7:0]  magnitude;  // amplitude of wave after multiplying with volume
	logic        waveOut;    // output signal.  PWM at 40MHz to achieve amplitude at 156.25 kHz
	logic        wgEn;       // interrrupt to request next amplitude from waveGen
	
	spi s(clk, reset, chipSelect, sck, sdi, tuneWord, volume);
	
	waveGen wg(clk, reset, wgEn, tuneWord, sign, amplitude);
	
	always_ff @(posedge clk) begin
		if (reset)    currentVol <= 8'b0;
		else if(wgEn) currentVol <= volume;
	end
	
	logic [15:0] mult;
	assign mult = ({8'b0, amplitude} * {8'b0, currentVol});
	assign magnitude = (mult[7] & ~&mult[15:8]) ? (mult[15:8] + 8'b1) : (mult[15:8]);
	// ^ note: rounding with saturation
	
	pwmGen pg(clk, reset, magnitude, wgEn, waveOut);
	
	outputGen og(clk, reset, waveOut, sign, A, B, C, D);
	
endmodule

module spi(input  logic clk, reset,
			  input  logic chipSelect,
			  input  logic sck, 
			  input  logic sdi,
			  output logic [15:0] tuneWord,
			  output logic [7:0]  volume);
	// Accepts frequency and volume input over SPI from ATSAM
	// Internal freq and volume only updated after full packet recieved
	// Note: contains ~3.4 second watchdog timer (turns off music)
	
	logic[4:0]  dataCount        = 5'b0; // amt of data in SPI packet so far
	logic       icanHasFlags     = 1'b0; // indicates whether readData is good
	logic       icanHasFlagsCopy = 1'b0; // copied into clk domain
	logic[23:0] readData;                // data recieved over SPI
	logic[23:0] readDataCopy;            // copied into clk domain
	logic[25:0] watchdogCounter;         // 2^27/40MHz = ~3.36 seconds %25:0
	logic       watchdogTriggered;
	logic[15:0] lastTuneWord;            // internal memory for feeding watchdog
	
	// assert chipSelect
	// shift in frequency in two bytes (MSB first)
	// shift in volume in one byte
	// deassert chipSelect or just repeat
	
	always_ff @(posedge sck or negedge chipSelect) begin
		if(~chipSelect) begin          
			dataCount    <= 5'b0;
		end
		else begin
			readData <= {readData[22:0], sdi};
			dataCount <= dataCount + 5'b1;
			if((dataCount + 5'b1) == 5'd24) icanHasFlags <= 1'b1;
			else                            icanHasFlags <= 1'b0;
		end
	end
	
	always_ff @(posedge clk) begin
		if(~chipSelect) begin // copy over from sck domain if cs is low
			readDataCopy     <= readData;
			icanHasFlagsCopy <= icanHasFlags;
		end
		
		if(reset) begin
			tuneWord          <= 16'b0;
			volume            <=  8'b0;
			watchdogCounter   <= 26'b0;
			watchdogTriggered <=  1'b0;
		end else begin
			if(&watchdogCounter & (readDataCopy[23:8] == lastTuneWord)) begin
				watchdogTriggered <=  1'b1; // stop playing
			end else begin
				watchdogCounter <= watchdogCounter + 26'b1;
			end
			if(icanHasFlagsCopy) begin
				if(watchdogTriggered) begin
					tuneWord <= 16'b0;
					volume   <=  8'b0;
				end else begin
					tuneWord <= readDataCopy[23:8];
					volume   <= readDataCopy[7:0];
				end
				lastTuneWord <= readDataCopy[23:8];
				if(~(readDataCopy[23:8] == lastTuneWord)) begin
					watchdogCounter   <= 26'b0;
					watchdogTriggered <= 1'b0;
				end
			end
		end
	end
endmodule

module waveGen(input  logic clk, reset, wgEn,
					input  logic[15:0] tuneWord,
					output logic       sign,
					output logic[7:0]  amplitude);
	// generates sinusoid based on tuneWord
	// only changes frequency at end of wave (every other zero crossing)
	
	logic[15:0] phaseAcc;             // phase accumulator
	logic[7:0]  LUTsine[(2**10-1):0]; // look up table
	logic[15:0] currentTuneWord;
	
	logic nextSign;
	logic[9:0] nextPhase;
	assign nextSign = phaseAcc[15]; // neg in second half
	assign nextPhase = (phaseAcc[14]) ? (10'b0 - phaseAcc[13:4]) : (phaseAcc[13:4]);
	// ^ note that phase is adjusted since we're using a 1/4 phase LUT
	
	always_ff @(posedge clk) begin
		if(reset) begin
			phaseAcc        <= 16'b0;
			currentTuneWord <= 16'b0;
			amplitude       <= 8'b0;
			sign            <= 1'b0;
		end
		else if(wgEn) begin
			if((tuneWord != currentTuneWord) & ((~sign & nextSign) | (currentTuneWord == 16'b0))) begin
				currentTuneWord <= tuneWord;
				phaseAcc        <= 16'b0;
				amplitude       <= 8'b0;
				sign            <= 1'b0;
			end else begin
				phaseAcc  <= phaseAcc + currentTuneWord;
				amplitude <= LUTsine[nextPhase];
				sign      <= nextSign;
			end
		end
	end
	
	initial begin
		$readmemb("LUTsine.txt", LUTsine);
	end
	
endmodule

module pwmGen(input  logic      clk, reset,
				  input  logic[7:0] magnitude,
				  output logic      wgEn,
				  output logic      waveOut);
	// modulates carrier signal based on sine wave

	// wave gen runs at 156.25 kHz = 40MHz / 256 (aka 2^8)
	logic[7:0] waveCounter;
	always_ff @(posedge clk) begin
		if(reset)  waveCounter <= 8'b10000000;
		else       waveCounter <= waveCounter + 8'b1;
	end
	assign wgEn = (waveCounter == 8'b0);
	
	always_ff @(posedge clk) begin
		waveOut <= (~reset & (waveCounter < magnitude));
		// PWM carrier by magnitude
	end
endmodule

module outputGen(input  logic clk, reset,
					  input  logic waveOut, sign,
					  output logic A, B, C, D);
	// generates FET driver signals based on sign and output wave
	// has 5 cycle dead time between driving in opposite directions
	// A = high side left
	// B = high side right
	// C = low side left (corresponds to B)
	// D = low side right (corresponds to A)
	
	// note: C should be on when either B is PWMing or when A
	// is not on if A is PWMing, and vice versa for D
	
	`define HIGHMINDELAY 2
	`define LOWMINDELAY  5
	logic nextA, nextB, nextC, nextD;
	logic[3:0] timeSinceLastA = 0;
	logic[3:0] timeSinceLastB = 0;
	logic[3:0] timeSinceLastC = 0;
	logic[3:0] timeSinceLastD = 0;
	
	always_ff @(posedge clk) begin
		if(reset) begin
			timeSinceLastA <= 0;
			timeSinceLastB <= 0;
			timeSinceLastC <= 0;
			timeSinceLastD <= 0;
		end else begin // note: A and B are inverted
			A <= ~(nextA & (timeSinceLastC > `HIGHMINDELAY));
			B <= ~(nextB & (timeSinceLastD > `HIGHMINDELAY));
			C <=  (nextC & (timeSinceLastA > `LOWMINDELAY));
			D <=  (nextD & (timeSinceLastB > `LOWMINDELAY));
			if(~A)                    timeSinceLastA <= 0;
			else if(~&timeSinceLastA) timeSinceLastA <= timeSinceLastA + 1;
			if(~B)                    timeSinceLastB <= 0;
			else if(~&timeSinceLastB) timeSinceLastB <= timeSinceLastB + 1;
			if( C)                    timeSinceLastC <= 0;
			else if(~&timeSinceLastC) timeSinceLastC <= timeSinceLastC + 1;
			if( D)                    timeSinceLastD <= 0;
			else if(~&timeSinceLastD) timeSinceLastD <= timeSinceLastD + 1;
		end
	end
	
	assign nextA = (waveOut & ~sign);
	assign nextB = (waveOut &  sign);
	assign nextC = (~nextA |  sign);
	assign nextD = (~nextB | ~sign);
	
endmodule
