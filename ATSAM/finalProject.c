// finalProject.c
// cnorfleet@hmc.edu, emeike@hmc.edu 15 November 2019
//
// Sends song notes and volumes to FPGA over SPI
// Note: store song pitch in Hz, dur in ms

#include <stdio.h>
#include "SAM4S4B_libraries/SAM4S4B.h"
#include "ArduboyTonesPitches.h"
#define TONES_END -1

const int blankTrack[] = { 0, 1, -1, -1 };

// Song to play:
#include "Songs/4channel/vivaLaVida.c"
#define NUM_TRACKS 4
const int* tracks[NUM_TRACKS] = { &(score1[0]), &(score2[0]), &(score3[0]), &(score4[0]) };

#define CHIP_SELECT_PIN PIO_PB10 // PB10 -> P126
#define CHIP_SELECT_PIN2 PIO_PA8
// SPCK: PA14 -> P113
// MOSI: PA13 -> P112
// MISO: PA12 -> P111
// NPCS0 (not used): PA11 -> P110

#define CH_ID     TC_CH0_ID
#define CLK_ID    TC_CLK5_ID
#define CLK_SPEED TC_CLK5_SPEED

unsigned int idx[NUM_TRACKS];
uint16_t currentTuneWord[NUM_TRACKS];
uint8_t  currentVolume = 0b11111111;
int remainingDur[NUM_TRACKS];
int currentDur = 0;
char bytes[NUM_TRACKS*3];

uint16_t getTuneWord(int pitch);
int getMinDur(void);
void updateTrackArray(int track);
void initTrackArrays(void);
char isAllRests(void);
char isStillPlaying(void);
void progressNotes(int timePassed);
void updateBytes(int track);
void sendNotes(void);

int main(void) {
	// Initialize:
  samInit();
  pioInit();
//	adcInit(ADC_MR_LOWRES_BITS_10);
//	adcChannelInit(ADC_CH0, ADC_CGR_GAIN_X1, ADC_COR_OFFSET_OFF);
  spiInit(MCK_FREQ/244000, 0, 1);
  // "clock divide" = master clock frequency / desired baud rate
  // the phase for the SPI clock is 0 and the polarity is 0
//	tcInit();
//	tcChannelInit(CH_ID, CLK_ID, TC_MODE_UP_RC);
	tcDelayInit();
	pioPinMode(CHIP_SELECT_PIN, PIO_OUTPUT);
	pioPinMode(CHIP_SELECT_PIN2, PIO_OUTPUT);
	
//	volatile uint32_t temp; // figure out adc volume control later
//	while(1)
//		temp = adcRead(ADC_CH0);

	// Get ready to play song:
	tcDelay(100); // allow for FPGA to start up
	initTrackArrays();
	while(isAllRests()) {
		progressNotes(getMinDur()); // skip rests at start
	}
	
	// Play song
	while (isStillPlaying()) {
		tcDelay(currentDur);
		progressNotes(currentDur);
		sendNotes();
		
		//tcResetChannel(CH_ID);
		//uint32_t noteEnd = dur * (CLK_SPEED / 1e3);
		//tcSetRC_compare(CH_ID, noteEnd);
		//while(tcCheckRC_compare(CH_ID)) { }
	}
	
	// stop playing at end of song:
	for(int i = 0; i < TONES_END; i++) {
		currentTuneWord[i] = 0;
		remainingDur[i] = -1;
		updateBytes(i);
	}
	sendNotes();
}

uint16_t getTuneWord(int pitch) {
	// note: tuneWord of 1 corresponds to 2.384 Hz = ((40MHz)/2^8)/2^16
	uint16_t tuneWord = pitch / 2.38418579;
	return tuneWord;
}

int getMinDur(void) {
	int minDur = tracks[0][2*idx[0]+1];
	for(int i = 1; i < NUM_TRACKS; i++) {
		if(remainingDur[i] < minDur) {
			minDur = remainingDur[i];
		}
	}
	return minDur;
}

void updateTrackArray(int track) {
	remainingDur[track] = tracks[track][2*idx[track]+1];
	currentTuneWord[track] = getTuneWord(tracks[track][2*idx[track]]);
}

void initTrackArrays(void) {
	for(int i = 0; i < NUM_TRACKS; i++) {
		idx[i] = 0;
		updateTrackArray(i);
	}
	currentDur = getMinDur();
}

char isAllRests(void) {
	for(int i = 0; i < NUM_TRACKS; i++) {
		if(currentTuneWord[i] != 0) {
			return 0;
		}
	}
	return 1;
}

char isStillPlaying(void) {
	for(int i = 0; i < NUM_TRACKS; i++) {
		if(remainingDur[i] != -1)
			return 1;
	}
	return 0;
}

void progressNotes(int timePassed) {
	// update tracks after timePassed (in ms)
	for(int i = 0; i < NUM_TRACKS; i++) {
		if(remainingDur[i] == -1) continue;
		remainingDur[i] = remainingDur[i] - timePassed;
		if(remainingDur[i] <= 0) { // continute to next note
			int lastRemainingDur = remainingDur[i];
			idx[i] = idx[i] + 1;
			if(tracks[i][2*idx[i]] == -1) { // at the end of this track
				currentTuneWord[i] = 0;
				remainingDur[i] = -1;
			} else {
				updateTrackArray(i);
				remainingDur[i] = remainingDur[i] + lastRemainingDur;
				// ^ if we've gone too far, subtract from next
			}
			updateBytes(i);
		}
	}
	currentDur = getMinDur();
}

void updateBytes(int track) {
	uint8_t tune_word_byte_1 = currentTuneWord[track] >> 8;
	uint8_t tune_word_byte_2 = currentTuneWord[track];
	uint8_t volume_byte = (currentTuneWord[track] == 0)
					? 0b00000000 : currentVolume; // pitch 0 is rest
	
	bytes[3*track]   = tune_word_byte_1;
	bytes[3*track+1] = tune_word_byte_2;
	bytes[3*track+2] = volume_byte;
}

void sendNotes(void) {
	// assert chipSelect
	// for each track:
	//   shift in frequency in two bytes
	//   shift in volume in one byte
	// deassert chipSelect
	pioDigitalWrite(CHIP_SELECT_PIN, 1);
	pioDigitalWrite(CHIP_SELECT_PIN2, 1);
	for(int i = 0; i < NUM_TRACKS*3; i++) {
		spiSendReceive(bytes[i]);
	}
	pioDigitalWrite(CHIP_SELECT_PIN, 0);
	pioDigitalWrite(CHIP_SELECT_PIN2, 0);
}

/*
use a RC_compare on a different channel for each track.
never reset channels if possible, use count up and start counting
again from bottom.  Calculate RC compare value to handle wraparound.
also have a separate index i for each track.
in main while loop, check all the RC compare triggers and also check
for uart webpage updates.  send html stuff over uart to esp.
also add a variable to keep track of whether or not a song is currently
playing and which song is playing
add html commands for pausing and continuing playing and also dynamically
setting volume.  maybe even let volume change mid-note in addition to
at the end of notes
hmmm.  maybe instead of using a lot of RC_compares and different channels,
find minimum time to next note change on any track since we might just send
every note over SPI every time any note is updated anyways
*/
