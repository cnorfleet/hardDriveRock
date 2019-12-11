// finalProject.c
// cnorfleet@hmc.edu, emeike@hmc.edu 15 November 2019
//
// Sends song notes and volumes to FPGA over SPI
// Note: store song pitch in Hz, dur in ms

#include <stdio.h>
#include <math.h>
#include "SAM4S4B_libraries/SAM4S4B.h"
#include "ArduboyTonesPitches.h"
#define TONES_END -1

const int blankTrack[] = { 0, 1, -1, -1 };

// Song to play:
//#include "Songs/4channel/vivaLaVida.c"
#include "Songs/4channel/onTopOfTheWorld.c"
//#include "Songs/4channel/cantinaBand.c"
//#include "Songs/4channel/justGiveMeAReason.c"
//#include "Songs/4channel/dancingQueen.c"
//#include "Songs/4channel/payphone.c"
#define NUM_TRACKS 4
const int* tracks[NUM_TRACKS] = { &(score1[0]), &(score2[0]), &(score3[0]), &(score4[0]) };
//const int* tracks[NUM_TRACKS] = { &(score[0]), &(score[0]), &(score[0]), &(score[0]) };

#define CHIP_SELECT_PIN PIO_PA8 // connected to Pin 55 on FPGA
// SPCK: PA14 -> P113
// MOSI: PA13 -> P112
// MISO: PA12 -> P111
// NPCS0 (not used): PA11 -> P110
#define PAUSE_PIN PIO_PA10
#define PLAY_PIN PIO_PA9

#define LED0 PIO_PA0
#define LED1 PIO_PA1
#define LED2 PIO_PA2
#define LED3 PIO_PA29
#define LED4 PIO_PA30
#define LED5 PIO_PA5
#define LED6 PIO_PA6
#define LED7 PIO_PA7

#define VOLUME_CH ADC_CH0 // volume selected with ADC CH 0 (PIN PA17)

#define CH_ID     TC_CH0_ID
#define CLK_ID    TC_CLK5_ID
#define CLK_SPEED TC_CLK5_SPEED

unsigned int idx[NUM_TRACKS];
uint16_t currentTuneWord[NUM_TRACKS];
uint8_t  currentVolume = 0b11111111;
int remainingDur[NUM_TRACKS]; // time in ms until next note change per track
int currentDur = 0;           // minumum time in ms until next note change
char bytes[NUM_TRACKS*3];     // byte data to send to FPGA over SPI
char paused = 0;              // indicates whether the sond is currently paused

uint16_t getTuneWord(int pitch);
int getMinDur(void);
void updateTrackArray(int track);
void initTrackArrays(void);
char isAllRests(void);
char isStillPlaying(void);
void progressNotes(int timePassed);
void updateVolume(void);
void updateBytes(int track);
void updateAllBytes(void);
void updateAllBytesForPaused(void);
void sendNotes(void);

int main(void) {
	// Initialize:
  samInit();
  pioInit();
	adcInit(ADC_MR_LOWRES_BITS_10);
	adcChannelInit(VOLUME_CH, ADC_CGR_GAIN_X1, ADC_COR_OFFSET_OFF);
  spiInit(MCK_FREQ/244000, 0, 1);
  // ^ "clock divide" = master clock frequency / desired baud rate
  // the phase for the SPI clock is 0 and the polarity is 0
	tcDelayInit();
	pioPinMode(CHIP_SELECT_PIN, PIO_OUTPUT);
	pioPinMode(PAUSE_PIN, PIO_INPUT);
	pioPinResistor(PAUSE_PIN, PIO_PULL_DOWN);
	pioPinMode(PLAY_PIN, PIO_INPUT);
	pioPinResistor(PLAY_PIN, PIO_PULL_DOWN);
	
	pioPinMode(LED0, PIO_OUTPUT);
	pioPinMode(LED1, PIO_OUTPUT);
	pioPinMode(LED2, PIO_OUTPUT);
	pioPinMode(LED3, PIO_OUTPUT);
	pioPinMode(LED4, PIO_OUTPUT);
	pioPinMode(LED5, PIO_OUTPUT);
	pioPinMode(LED6, PIO_OUTPUT);
	pioPinMode(LED7, PIO_OUTPUT);

	// Get ready to play song:
	tcDelay(10); // allow for FPGA to start up
	initTrackArrays();
	while(isAllRests()) {
		progressNotes(getMinDur()); // skip rests at start
	}
	
	// Play song:
	while (isStillPlaying()) {
		if(!paused) {
			tcDelay(currentDur);
			progressNotes(currentDur);
			updateVolume();
			sendNotes();
		}
		if(paused && pioDigitalRead(PLAY_PIN)) // resume playing
			paused = 0;
		else if(!paused && pioDigitalRead(PAUSE_PIN)) { // pause
			updateAllBytesForPaused();
			sendNotes();
			paused = 1;
		}
	}
	
	// stop playing at end of song:
	for(int i = 0; i < TONES_END; i++) {
		currentTuneWord[i] = 0;
		remainingDur[i] = -1;
		updateBytes(i);
	}
	sendNotes();
	
	// keep displaying current volume on LEDs even after song ends:
	while(1) {
		updateVolume();
	}
}

uint16_t getTuneWord(int pitch) {
	// note: tuneWord of 1 corresponds to 2.384 Hz = ((40MHz)/2^8)/2^16
	uint16_t tuneWord = pitch / 2.38418579;
	return tuneWord;
}

int getMinDur(void) {
	int minDur = tracks[0][2*idx[0]+1];
	for(int i = 1; i < NUM_TRACKS; i++) {
		if((minDur == -1) || ((remainingDur[i] != -1) && (remainingDur[i] < minDur))) {
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
	return (currentDur != -1);
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

void updateVolume(void) {
	// measure voltage from pin and convert to value between 0 and 1
	float voltage = adcRead(VOLUME_CH);
	double volumeScale = voltage / 3.3;
	volumeScale = (volumeScale > 1) ? 1 : volumeScale;
	volumeScale = (volumeScale < 0) ? 0 : volumeScale;
	
	uint8_t newVolume = (int) (round(volumeScale * 0b11111111));
	if(newVolume != currentVolume) {
		currentVolume = newVolume;
		updateAllBytes();
	}
	pioDigitalWrite(LED0, (currentVolume)      & 1);
	pioDigitalWrite(LED1, (currentVolume >> 1) & 1);
	pioDigitalWrite(LED2, (currentVolume >> 2) & 1);
	pioDigitalWrite(LED3, (currentVolume >> 3) & 1);
	pioDigitalWrite(LED4, (currentVolume >> 4) & 1);
	pioDigitalWrite(LED5, (currentVolume >> 5) & 1);
	pioDigitalWrite(LED6, (currentVolume >> 6) & 1);
	pioDigitalWrite(LED7, (currentVolume >> 7) & 1);
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

void updateAllBytes(void) {
	for(int i = 0; i < NUM_TRACKS; i++)
		updateBytes(i);
}

void updateAllBytesForPaused(void) {
	for(int i = 0; i < NUM_TRACKS*3; i++)
		bytes[i] = 0b00000000;
}

void sendNotes(void) {
	// assert chipSelect
	// for each track:
	//   shift in frequency in two bytes
	//   shift in volume in one byte
	// deassert chipSelect
	pioDigitalWrite(CHIP_SELECT_PIN, 1);
	for(int i = 0; i < NUM_TRACKS*3; i++) {
		spiSendReceive(bytes[i]);
	}
	pioDigitalWrite(CHIP_SELECT_PIN, 0);
}
