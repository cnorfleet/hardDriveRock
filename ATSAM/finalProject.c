// finalProject.c
// cnorfleet@hmc.edu, emeike@hmc.edu 15 November 2019
//
// Sends song notes and volumes to FPGA over SPI

#include <stdio.h>
#include "SAM4S4B_libraries/SAM4S4B.h"
#include "ArduboyTonesPitches.h"

#define TONES_END -1
#include "Songs/su.c"

#define PLAYGENERATEDSONG 1

#define SONGMODESWITCH  PIO_PB2
#define CHIP_SELECT_PIN PIO_PB10 // PB10 -> P126
#define CHIP_SELECT_PIN2 PIO_PA8
// SPCK: PA14 -> P113
// MOSI: PA13 -> P112
// MISO: PA12 -> P111
// NPCS0 (not used): PA11 -> P110

#define CH_ID     TC_CH0_ID
#define CLK_ID    TC_CLK5_ID
#define CLK_SPEED TC_CLK5_SPEED

// Pitch in Hz, duration in ms
// Fur Elise
const int song1[][2] = {
{659,	125},
{623,	125},
{659,	125},
{623,	125},
{659,	125},
{494,	125},
{587,	125},
{523,	125},
{440,	250},
{  0,	125},
{262,	125},
{330,	125},
{440,	125},
{494,	250},
{  0,	125},
{330,	125},
{416,	125},
{494,	125},
{523,	250},
{  0,	125},
{330,	125},
{659,	125},
{623,	125},
{659,	125},
{623,	125},
{659,	125},
{494,	125},
{587,	125},
{523,	125},
{440,	250},
{  0,	125},
{262,	125},
{330,	125},
{440,	125},
{494,	250},
{  0,	125},
{330,	125},
{523,	125},
{494,	125},
{440,	250},
{  0,	125},
{494,	125},
{523,	125},
{587,	125},
{659,	375},
{392,	125},
{699,	125},
{659,	125},
{587,	375},
{349,	125},
{659,	125},
{587,	125},
{523,	375},
{330,	125},
{587,	125},
{523,	125},
{494,	250},
{  0,	125},
{330,	125},
{659,	125},
{  0,	250},
{659,	125},
{1319,125},
{  0,	250},
{623,	125},
{659,	125},
{  0,	250},
{623,	125},
{659,	125},
{623,	125},
{659,	125},
{623,	125},
{659,	125},
{494,	125},
{587,	125},
{523,	125},
{440,	250},
{  0,	125},
{262,	125},
{330,	125},
{440,	125},
{494,	250},
{  0,	125},
{330,	125},
{416,	125},
{494,	125},
{523,	250},
{  0,	125},
{330,	125},
{659,	125},
{623,	125},
{659,	125},
{623,	125},
{659,	125},
{494,	125},
{587,	125},
{523,	125},
{440,	250},
{  0,	125},
{262,	125},
{330,	125},
{440,	125},
{494,	250},
{  0,	125},
{330,	125},
{523,	125},
{494,	125},
{440,	500},
{  0,	  1}, // stop
{  0,	 -1}};

// Pitch in Hz, duration in ms
// Hedwig's Theme
const int song2[][2] = {
{ 494, 125 }, // B5
{ 659, 187 }, // E5
{ 784, 63  }, // G5
{ 740, 125 }, // F#5
{ 659, 250 }, // E5
{ 988, 125 }, // B6
{ 880, 375 }, // A6
{ 740, 375 }, // F#5
{ 659, 187 }, // E5
{ 784, 63  }, // G5
{ 740, 125 }, // F#5
{ 622, 250 }, // D#5
{ 698, 125 }, // Fnat5
{ 494, 625 }, // B5
{ 494, 125 }, // B5
{ 659, 187 }, // E5
{ 784, 63  }, // G5
{ 740, 125 }, // F#5
{ 659, 250 }, // E5
{ 988, 125 }, // B6
{ 1175,250 }, // D6
{ 1109,125 }, // C#6
{ 1047,250 }, // Cnat6
{ 831, 125 }, // Aflat6
{ 1047,187 }, // C6
{ 988, 63  }, // B6
{ 932, 125 }, // Bflat6
{ 466, 250 }, // Bflat5
{ 784, 125 }, // G5
{ 659, 625 }, // E5
{ 784, 125 }, // G5
{ 988, 250 }, // B6
{ 784, 125 }, // G5
{ 988, 250 }, // B6
{ 784, 125 }, // G5
{ 1047,250 }, // C6
{ 988, 125 }, // B6
{ 932, 250 }, // Bflat6
{ 740, 125 }, // F#5
{ 784, 187 }, // G5
{ 1047,63  }, // C6
{ 988, 125 }, // Bnat6
{ 466, 250 }, // Bflat5
{ 494, 125 }, // B5
{ 988, 625 }, // Bnat6
{ 784, 125 }, // G5
{ 988, 250 }, // B6
{ 784, 125 }, // G5
{ 988, 250 }, // B6
{ 784, 125 }, // G5
{ 1175,250 }, // D6
{ 1109,125 }, // Dflat6
{ 1047,250 }, // C6
{ 831, 125 }, // Aflat6
{ 1047,187 }, // C6
{ 988, 63  }, // B6
{ 932, 125 }, // Bflat6
{ 466, 250 }, // Bflat5
{ 784, 125 }, // G5
{ 659 ,625 }, // E5
{  0,	  1}, // stop
{  0,  -1 }};

// near middle C:      A    B    C    D    E    F    G
const int notes[] = { 196, 220, 240, 262, 294, 312, 350 }; // Hz

void playNote(int pitch, int dur);

int main(void) {
	// Initialize:
  samInit();
  pioInit();
  spiInit(MCK_FREQ/244000, 0, 1);
  // "clock divide" = master clock frequency / desired baud rate
  // the phase for the SPI clock is 0 and the polarity is 0
	//tcInit();
	//tcChannelInit(CH_ID, CLK_ID, TC_MODE_UP_RC);
	tcDelayInit();
	pioPinMode(CHIP_SELECT_PIN, PIO_OUTPUT);
	pioPinMode(CHIP_SELECT_PIN2, PIO_OUTPUT);

	// Read desired song mode:
	int songMode = pioDigitalRead(SONGMODESWITCH);
#if PLAYGENERATEDSONG
	const int * notes =  score;
	const double speedMult = 1;
	const int pitchMult = 1;
#else
	const int * notes = songMode ? &(song1[0][0]) : &(song2[0][0]);
	const int speedMult = songMode ? 1 : 3;
	const int pitchMult = songMode ? 1 : 2;
#endif

	// Play song:
	int i = 0;
	while (notes[i*2]) { i++; } // skip rests at start
	while (notes[i*2] != -1) {  // stop at TONES_END
		playNote(notes[i*2] / pitchMult, notes[i*2+1] * speedMult);
		i++;
	}
}

void playNote(int pitch, int dur) {
	// pitch in Hz, dur in ms
	
	//tcResetChannel(CH_ID);
	//uint32_t noteEnd = dur * (CLK_SPEED / 1e3);
	//tcSetRC_compare(CH_ID, noteEnd);
	
	// note: tuneWord of 1 corresponds to 2.384 Hz = ((40MHz)/2^8)/2^16
	uint16_t tuneWord = pitch / 2.38418579;
	char tune_word_byte_1 = tuneWord >> 8;
	char tune_word_byte_2 = tuneWord;
	char volume_byte = (pitch == 0) ? 0b00000000 : 0b11111111; // pitch 0 is rest
	
	// assert chipSelect
	// shift in frequency in two bytes
	// shift in volume in one byte
	// deassert chipSelect
	pioDigitalWrite(CHIP_SELECT_PIN, 1);
	pioDigitalWrite(CHIP_SELECT_PIN2, 1);
	spiSendReceive(tune_word_byte_1);
	spiSendReceive(tune_word_byte_2);
	spiSendReceive(volume_byte);
	pioDigitalWrite(CHIP_SELECT_PIN, 0);
	pioDigitalWrite(CHIP_SELECT_PIN2, 0);
	
	tcDelay(dur);
	//while(tcCheckRC_compare(CH_ID)) { }
}
