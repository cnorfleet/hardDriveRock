// finalProject.c
// cnorfleet@hmc.edu, emeike@hmc.edu 15 November 2019
//
// Sends song notes and volumes to FPGA over SPI

#include <stdio.h>
#include "SAM4S4B_libraries/SAM4S4B.h"

#define SONGMODESWITCH  PIO_PB2
#define CHIP_SELECT_PIN PIO_PB10 // PB10 -> P126
// SPCK: PA14 -> P113
// MOSI: PA13 -> P112
// MISO: PA12 -> P111
// NPCS0 (not used): PA11 -> P110

#define CH_ID     TC_CH0_ID
#define CLK_ID    TC_CLK4_ID
#define CLK_SPEED TC_CLK4_SPEED

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
{  0,	  0}};

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
{    0,  0 }};

// near middle C:      A    B    C    D    E    F    G
const int notes[] = { 196, 220, 240, 262, 294, 312, 350 }; // Hz

void playNote(int pitch, int dur);

int main(void) {
	// Initialize:
  samInit();
  pioInit();
  spiInit(MCK_FREQ/244000, 0, 1);
  // "clock divide" = master clock frequency / desired baud rate
  // the phase for the SPI clock is 1 and the polarity is 0
	tcInit();
	tcChannelInit(CH_ID, CLK_ID, TC_MODE_UP_RC);

	// Read desired song mode:
	int songMode = pioDigitalRead(SONGMODESWITCH);
	const int * notes = songMode ? &(song1[0][0]) : &(song2[0][0]);
	const int speedMult = songMode ? 1 : 3;
	const int pitchMult = songMode ? 1 : 2;

	// Play song:
	int i = 0;
	while (notes[i*2+1]) { // stop when duration is 0
		playNote(notes[i*2] / pitchMult, notes[i*2+1] * speedMult);
		i++;
	}
}

void playNote(int pitch, int dur) {
	// pitch in Hz, dur in ms
	
	tcResetChannel(CH_ID);
	uint32_t noteEnd = dur * (CLK_SPEED / 1e3);
	tcSetRC_compare(CH_ID, noteEnd);
	
	// TODO: switch freq to the tune word?
	char FREQ_BYTE_1 = pitch >> 8;
	char FREQ_BYTE_2 = pitch;
	char VOLUME_BYTE = (pitch == 0) ? 0b00000000 : 0b11111111; // pitch 0 is rest
	
	// assert chipSelect
	// shift in frequency in two bytes
	// shift in volume in one byte
	// deassert chipSelect
	pioDigitalWrite(CHIP_SELECT_PIN, 1);
	spiSendReceive(FREQ_BYTE_1);
	spiSendReceive(FREQ_BYTE_2);
	spiSendReceive(VOLUME_BYTE);
	pioDigitalWrite(CHIP_SELECT_PIN, 0);
	
	while(tcCheckRC_compare(CH_ID)) { }
}
