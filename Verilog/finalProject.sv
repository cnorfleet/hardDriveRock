// finalProject.sv
// Erik Meike and Caleb Norfleet
// FPGA stuff for uPs final project

typedef enum logic { PWM, PDM } OUTPUT_TYPES;

`define PACKET_SIZE 24 // bits of data per track in each packet
typedef logic[`PACKET_SIZE-1:0] packetType;

module top #(parameter              NUM_TRACKS  = 4,   // number of tracks (and tone generators) used
				 parameter OUTPUT_TYPES OUTPUT_TYPE = PWM) // method of producing output signal from amplitude
				(input  logic                 clk, reset,
				 input  logic                 chipSelect, sck, sdi,
				 output logic[NUM_TRACKS-1:0] leftHigh, leftEn, rightHigh, rightEn);
	
	packetType[NUM_TRACKS-1:0] notePackets;
	
	spi #(NUM_TRACKS) s(clk, reset, chipSelect, sck, sdi, notePackets);
	
	noteCore #(OUTPUT_TYPE) nc[NUM_TRACKS-1:0](
	 .clk        ( clk ),         // single bit replicated across instance array
	 .reset      ( reset ),
	 .notePacket ( notePackets ), // connected logic wider than port so split across instances
	 .leftHigh   ( leftHigh ),
	 .leftEn     ( leftEn ),
	 .rightHigh  ( rightHigh ),
	 .rightEn    ( rightEn )
	);
	
endmodule

module noteCore #(parameter OUTPUT_TYPES OUTPUT_TYPE = PWM)
					  (input  logic      clk, reset,
						input  packetType notePacket,
						output logic      leftHigh, leftEn, rightHigh, rightEn);
	// tone generator for one track
	
	logic[15:0] tuneWord;   // frequency of note signal
	logic[7:0]  volume;     // unsigned volume of output
	logic       sign;       // note signal sign
	logic[7:0]  amplitude;  // note signal amplitude
	logic[7:0]  currentVol; // volume only updated after every 2^8 clock cycles
	logic[7:0]  magnitude;  // amplitude of wave after multiplying with volume
	logic       waveOut;    // output signal.  PWM at 40MHz to achieve amplitude at 156.25 kHz
	logic       wgEn;       // interrrupt to request next amplitude from waveGen
	
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
	
//	if(OUTPUT_TYPE === PWM) // TODO: figure out how to do this conditionally
		pwmGen pg(clk, reset, magnitude, wgEn, waveOut);
//	else
//		pdmGen pg(clk, reset, magnitude, wgEn, waveOut);
	
	outputGen og(clk, reset, waveOut, sign, leftHigh, leftEn, rightHigh, rightEn);
	
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
	// uses pulse width modulation (width of pulses reflects amplitude)
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

module pdmGen(input  logic      clk, reset,
				  input  logic[7:0] magnitude,
				  output logic      wgEn,
				  output logic      waveOut);
	// modulates carrier signal based on sine wave
	// uses pulse width modulation (density of pulses reflects amplitude)
	// wave gen runs at 156.25 kHz = 40MHz / 256 (aka 2^8)
	
	logic[7:0] waveCounter;
	always_ff @(posedge clk) begin
		if(reset)  waveCounter <= 8'b10000000;
		else       waveCounter <= waveCounter + 8'b1;
	end
	assign wgEn = (waveCounter == 8'b0);
	
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
	logic       icanHasFlags     = 1'b0;  // indicates whether readData is good
	logic       icanHasFlagsCopy = 1'b0;  // copied into clk domain
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
					icanHasFlags <= 1'b1;
			else	icanHasFlags <= 1'b0;
		end
	end
	
	always_ff @(posedge clk) begin
		if(~chipSelect) begin // copy over from sck domain if cs is low
			readDataCopy     <= readData;
			icanHasFlagsCopy <= icanHasFlags;
		end
		
		if(reset) begin
			notePackets       <= {NUM_TRACKS*`PACKET_SIZE{1'b0}};
			watchdogCounter   <= 26'b0;
			watchdogTriggered <=  1'b0;
		end else begin
			if(&watchdogCounter & (readDataCopy == lastReadData)) begin
				watchdogTriggered <=  1'b1;               // stop playing if watchdog counter at max val
			end else begin
				watchdogCounter <= watchdogCounter + 26'b1;
			end
			if(icanHasFlagsCopy) begin                   // if the packet is valid, update tracks
				if(watchdogTriggered) begin               // if watchdog triggered, don't play
					notePackets <= {NUM_TRACKS*`PACKET_SIZE{1'b0}};
				end else begin                            // otherwise update tracks with current note
					notePackets <= readDataCopy;
				end
				lastReadData <= readDataCopy;
				if(~(readDataCopy == lastReadData)) begin // if we've recieved a new packet, feed watchdog
					watchdogCounter   <= 26'b0;
					watchdogTriggered <= 1'b0;
				end
			end
		end
	end
endmodule
