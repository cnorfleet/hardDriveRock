// finalProject.sv
// Erik Meike and Caleb Norfleet
// FPGA stuff for uPs final project

// method of producing output signal from amplitude:
//`define USING_PWM
`define USING_PDM

`define PACKET_SIZE 24 // bits of data per track in each packet
typedef logic[`PACKET_SIZE-1:0] packetType;

module top #(parameter NUM_INPUTS  = 4, // number of tracks (tone generators)
				 parameter NUM_OUTPUTS = 4) // number of output channels
				(input  logic                  clk, reset,
				 input  logic                  chipSelect, sck, sdi,
				 output logic[NUM_OUTPUTS-1:0] leftHigh, leftEn, rightHigh, rightEn);
	
	packetType[NUM_INPUTS-1:0] notePackets; // spi packets for each track
	logic     [NUM_INPUTS-1:0] sign;        // note signal sign for each track
	logic[NUM_INPUTS-1:0][7:0] magnitude;   // magnitude of note signal (multiplied with volume)
	
	logic[7:0] waveCounter; // keeps track of position between amplitude updates, needed for PWM
	logic      wgEn;        // interrrupt to request next amplitude from waveGen
	
	spi #(NUM_INPUTS) s(clk, reset, chipSelect, sck, sdi, notePackets);
	
	toneGenerator tg[NUM_INPUTS-1:0](
	 .clk        ( clk ),         // single bit replicated across instance array
	 .reset      ( reset ),
	 .notePacket ( notePackets ), // connected logic wider than port so split across instances
	 .wgEn       ( wgEn ),
	 .sign       ( sign ),
	 .magnitude  ( magnitude )
	);
	
	amplitudeUpdateCounter auc(clk, reset, waveCounter, wgEn);
	
	// convert two inputs into one output:
	// TODO: organize this into a nice configurable module or something
	logic[9:0] magnitude0, magnitude1, magSum, magSumTwosComplement;
	logic[7:0] outputMagnitude;
	logic      outputSign;
	// note: first convert to two's complement for easy addition
	assign magnitude0 = {{2{sign[0]}}, (~(sign[0]) ? magnitude[0] : ~(magnitude[0]))} + (sign[0]);
	assign magnitude1 = {{2{sign[1]}}, (~(sign[1]) ? magnitude[1] : ~(magnitude[1]))} + (sign[1]);
	assign magSum = magnitude0 + magnitude1;
	assign magSumTwosComplement = (~magSum + 10'b1);
	assign outputSign = magSum[9];
	assign outputMagnitude = ~outputSign ? magSum[8:1] : magSumTwosComplement[8:1];
	
	outputChannel oc[NUM_OUTPUTS-1:0](
	 .clk         ( clk ),
	 .reset       ( reset ),
	 .sign        ( outputSign ),
	 .magnitude   ( outputMagnitude ),
	 .waveCounter ( waveCounter ),
	 .leftHigh    ( leftHigh ),
	 .leftEn      ( leftEn ),
	 .rightHigh   ( rightHigh ),
	 .rightEn     ( rightEn )
	);
	
endmodule

module toneGenerator(input  logic      clk, reset,
							input  packetType notePacket,
							input  logic      wgEn,
							output logic      sign,
							output logic[7:0] magnitude);
	// tone generator for one track
	// produces amplitude and sign for that track's note signal
	
	logic[15:0] tuneWord;   // frequency of note signal
	logic[7:0]  volume;     // unsigned volume of output
	logic[7:0]  currentVol; // volume only updated after every 2^8 clock cycles
	logic[7:0]  amplitude;  // amplitude of note signal (before multiplying with volume)
	
	assign tuneWord = notePacket[23:8];
	assign volume   = notePacket[ 7:0];
	
	waveGen wg(clk, reset, wgEn, tuneWord, sign, amplitude);
	
	always_ff @(posedge clk) begin
		if (reset)    currentVol <= 8'b0;
		else if(wgEn) currentVol <= volume;
	end
	
	logic[15:0] mult;
	assign mult = ({8'b0, amplitude} * {8'b0, currentVol});
	assign magnitude = (mult[7] & ~&mult[15:8]) ? (mult[15:8] + 8'b1) : (mult[15:8]);
	// ^ note: rounding with saturation
	
endmodule

module outputChannel(input  logic      clk, reset,
							input  logic      sign,
							input  logic[7:0] magnitude,
							input  logic[7:0] waveCounter,
							output logic      leftHigh, leftEn, rightHigh, rightEn);
	// output channel for one output line
	// produces output signals based on amplitude and sign
	
	logic waveOut; // output signal. Modulated at 40MHz to achieve amplitude at 156.25 kHz
	
	// generate our waveOut signal using the method of choice from OUTPUT_TYPES
	`ifndef USING_PWM
	`ifndef USING_PDM
	`define USING_PWM
	`endif
	`endif
	`ifdef USING_PWM
		pwmGen pg(clk, reset, magnitude, waveCounter, waveOut);
	`endif
	`ifdef USING_PDM
		pdmGen pg(clk, reset, magnitude, waveOut);
	`endif
	
	outputGen og(clk, reset, waveOut, sign, leftHigh, leftEn, rightHigh, rightEn);
	
endmodule

module waveGen(input  logic clk, reset, wgEn,
					input  logic[15:0] tuneWord,
					output logic       sign,
					output logic[7:0]  amplitude);
	// generates sinusoid based on tuneWord
	// only changes frequency at end of wave (every other zero crossing)
	
	logic[15:0] phaseAcc;             // phase accumulator
	logic[13:0] flippedPhase;         // phase "flipped" for segments of wave which are read backwards
	logic[7:0]  LUTsine[(2**10-1):0]; // look up table
	logic[15:0] currentTuneWord;
	
	logic nextSign;
	logic[9:0] nextPhase;
	assign nextSign = phaseAcc[15]; // neg in second half
	assign flippedPhase = 14'b0 - phaseAcc[13:0];
	assign nextPhase = (phaseAcc[14]) ? (flippedPhase[13:4]) : (phaseAcc[13:4]);
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
				  input  logic[7:0] waveCounter,
				  output logic      waveOut);
	// modulates carrier signal based on sine wave
	// uses pulse width modulation (width of pulses reflects amplitude)
	
	always_ff @(posedge clk) begin
		waveOut <= (~reset & (waveCounter < magnitude));
	end
	
endmodule

module pdmGen(input  logic      clk, reset,
				  input  logic[7:0] magnitude,
				  output logic      waveOut);
	// modulates carrier signal based on sine wave
	// uses pulse width modulation (density of pulses reflects amplitude)
	// wave gen runs at 156.25 kHz = 40MHz / 256 (aka 2^8)
	
	logic[8:0] acc, nextAcc;
	assign nextAcc = ({1'b0, acc[7:0]} + {1'b0, magnitude});
	always_ff @(posedge clk) begin
		if(reset) acc <= 9'b0;
		else      acc <= nextAcc;
		waveOut <= (~reset & nextAcc[8]);
		// assert output when acc overflows.  this means that the density with
		// which output is high reflects the amplitude
	end
endmodule

module amplitudeUpdateCounter(input  logic      clk, reset,
										output logic[7:0] waveCounter,
										output logic      wgEn);
	// wave gen runs at 156.25 kHz = 40MHz / 256 (aka 2^8)
	
	always_ff @(posedge clk) begin
		if(reset)  waveCounter <= 8'b10000000;
		else       waveCounter <= waveCounter + 8'b1;
	end
	assign wgEn = (waveCounter == 8'b0);
	
endmodule

module outputGen(input  logic clk, reset,
					  input  logic waveOut, sign,
					  output logic leftHigh, leftEn, rightHigh, rightEn);
	// generates FET driver signals based on sign and output wave
	
	always_ff @(posedge clk) begin
		if(reset) begin
			leftHigh  <= 1'b0;
			leftEn    <= 1'b0;
			rightHigh <= 1'b0;
			rightEn   <= 1'b0;
		end else begin
			leftEn    <= 1;
			rightEn   <= 1;
			leftHigh  <= ( sign)&waveOut; //  sign^waveOut
			rightHigh <= (~sign)&waveOut; //~(sign^waveOut)
		end
	end
	
endmodule

module spi #(parameter NUM_TRACKS = 4)
				(input  logic clk, reset,
				 input  logic chipSelect, sck, sdi,
				 output packetType[NUM_TRACKS-1:0] notePackets);
	// Accepts frequency and volume input over SPI from ATSAM
	// Internal freq and volume only updated after full packet recieved
	// Note: contains ~3.4 second watchdog timer (turns off music)
	
	// SPI interface protocol:
	//   assert chipSelect
	//   for each track (in order):
	//     shift in frequency in two bytes (MSB first)
	//     shift in volume in one byte
	//   deassert chipSelect
	
	logic[31:0] dataCount        = 32'b0; // amt of data in SPI packet so far
	logic       iCanHasFlags     = 1'b0;  // indicates whether readData is good
	logic       iCanHasFlagsCopy = 1'b0;  // copied into clk domain
	logic[25:0] watchdogCounter;          // 2^27/40MHz = ~3.36 seconds %25:0
	logic       watchdogTriggered;
	
	logic[(`PACKET_SIZE*NUM_TRACKS)-1:0] readData;     // data recieved over SPI
	logic[(`PACKET_SIZE*NUM_TRACKS)-1:0] readDataCopy; // copied into clk domain
	logic[(`PACKET_SIZE*NUM_TRACKS)-1:0] lastReadData; // internal memory for feeding watchdog
	
	always_ff @(posedge sck or negedge chipSelect) begin
		if(~chipSelect) begin          
			dataCount    <= 32'b0;
		end
		else begin
			readData <= {readData[(`PACKET_SIZE*NUM_TRACKS)-2:0], sdi};
			dataCount <= dataCount + 32'b1;
			if((dataCount + 32'b1) == (`PACKET_SIZE*NUM_TRACKS))
					iCanHasFlags <= 1'b1;
			else	iCanHasFlags <= 1'b0;
		end
	end
	
	always_ff @(posedge clk) begin
		// copy over from sck domain if cs is low:
		if(reset) begin
			readDataCopy      <= {NUM_TRACKS*`PACKET_SIZE{1'b0}};
			iCanHasFlagsCopy  <= 1'b0;
		end else if(~chipSelect) begin
			readDataCopy     <= readData;
			iCanHasFlagsCopy <= iCanHasFlags;
		end
		
		// update note packets when valid and keep track of watchdog:
		if(reset) begin
			notePackets       <= {NUM_TRACKS*`PACKET_SIZE{1'b0}};
			watchdogCounter   <= 26'b0;
			watchdogTriggered <=  1'b0;
		end else begin
			if(&watchdogCounter & (readDataCopy == lastReadData)) begin
				watchdogTriggered <=  1'b1; // stop playing if watchdog counter at max val
			end else begin
				watchdogCounter <= watchdogCounter + 26'b1;
			end
			if(iCanHasFlagsCopy & ~watchdogTriggered) begin
				notePackets <= readDataCopy; // if the packet is valid, update tracks with current note
			end else begin
				notePackets <= {NUM_TRACKS*`PACKET_SIZE{1'b0}}; // if watchdog is triggered, don't play
			end
			if(iCanHasFlagsCopy) begin
				lastReadData <= readDataCopy;
				if(~(readDataCopy == lastReadData)) begin // if we've recieved a new packet, feed watchdog
					watchdogCounter   <= 26'b0;
					watchdogTriggered <= 1'b0;
				end
			end
		end
	end
endmodule
