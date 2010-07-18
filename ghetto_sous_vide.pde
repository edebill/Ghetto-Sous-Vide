#include <util/crc16.h>
#include <avr/sleep.h>

// http://code.google.com/p/max6675-arduino-library/
#include <MAX6675.h>

int SO = 13;              // SO pin of MAX6675
int CS = 12;              // CS pin on MAX6675
int SCK = 11;             // SCK pin of MAX6675
int units = 0;            // Units to readout temp (0 = ˚F, 1 = ˚C)
float max6675_error = 0.0;        // Temperature compensation error
float temperature = 0.0;  // Temperature output variable


// Initialize the MAX6675 Library

MAX6675 temp0(CS, SO, SCK, units, max6675_error);

#include <LCD4Bit.h> 
//create object to control an LCD.  
//number of lines in display=1
LCD4Bit lcd = LCD4Bit(2);


//  how do we identify ourselves to the logging application?
#define source "ghetto sous vide"

//  connected to pin 9 on XBee, with a pullup resistor (100K seems good)
//  This is used to take the Xbee in and out of sleep mode
#define XBEE_PIN 8



#ifndef cbi
#define cbi(sfr, bit) (_SFR_BYTE(sfr) &= ~_BV(bit))
#endif
#ifndef sbi
#define sbi(sfr, bit) (_SFR_BYTE(sfr) |= _BV(bit))
#endif

#ifndef HAVE_XBEE
//#define HAVE_XBEE
#endif


#ifndef HAVE_XBEE_SLEEP
//#define HAVE_XBEE_SLEEP
#endif


// for timeout, waiting for response
uint16_t wait_start;
uint16_t wait_end;

// crc for our logging message
char crchex[5];


void setup(void) {
  lcd.init();

  // initialize inputs/outputs
  // start serial port
  xbee_wake();
  Serial.begin(9600);

#ifdef HAVE_XBEE_SLEEP  

  Serial.print("+++");

  char thisByte = 0;
  while (thisByte != '\r') {
    if (Serial.available() > 0) {
      thisByte = Serial.read();
    }
  }
  Serial.print("ATSM1\r");
  Serial.print("ATCN\r");

  delay(10);
#endif

  error("booting");

  delay(100);

  xbee_sleep();
}

void loop(void) {
  float reading;
  
  
  Serial.begin(9600);
  reading = read_data();

  // if reading is outside range (probably DEVICE_DISCONNECTED) don't log it
  if(reading > -67) {
    char buff[10];

    format_float(reading, buff);

    lcd.clear();
    lcd.printIn(buff);

    //	transmit_data(reading);
    Serial.println(buff);
  }


  delay(1000);

}

void xbee_wake(){
#ifdef HAVE_XBEE
  pinMode(XBEE_PIN, OUTPUT);
  digitalWrite(XBEE_PIN, HIGH);
  delay(5);
  digitalWrite(XBEE_PIN, LOW);
  delay(15);
#endif
}

void xbee_sleep(){
#ifdef HAVE_XBEE
  digitalWrite(XBEE_PIN, HIGH);
  pinMode(XBEE_PIN, INPUT);
#endif
}


// individual readings are bad 20% or more of the time
// give ourself NUM_TRIES to get NUM_READINGS good ones, then
// return the median of the good ones.  If we can't get
// 3 good ones in NUM_TRIES, return DEVICE_DISCONNECTED (the
// error return code that comes back from DallasTemperature)
// DEVICE_DISCONNECTED == -1766.19 F, well outside the
// valid reading range for this device.
float read_data(){
#define NUM_TRIES 20
#define NUM_READINGS 3

  return temp0.read_temp(NUM_READINGS);
}


void transmit_data(float temperature) {
  char buff[10];

  format_float(temperature, buff);

  send_temperature("T", source, buff);
}

void format_float(float temperature, char *buff) {
  // sprintf on arduino doesn't support floats
  char sign[2];
  
  if(temperature < 0) {
    strcpy(sign,"-");
  } else {
    sign[0] = '\0';
  }

  int decimal = (temperature - (int)temperature) * 100;

  sprintf(buff, "%s%d.%02d", sign, (int)abs(temperature), abs(decimal));
}


// send temperature to server, looking for a receipt message.
//  try 3 times, then give up
void send_temperature(char *type, char *source_name, char *data) {
  int crc = calculate_crc(type, source_name, data);
  sprintf(crchex, "%04X", crc);

  empty_input_buffer();
  int try_count = 1;
  send_msg(type, source_name, data, crchex);

  while( (3 > try_count) &&  (! check_for_receipt(crchex))) {

    delay(1000);
    delay(random(1000));

    send_msg(type, source_name, data, crchex);
    try_count++;
  }
}

void send_msg(char *type, char *source_name, char *data, char *crchex) {
  Serial.print(type);
  Serial.print(":");
  Serial.print(source_name);
  Serial.print(":");
  Serial.print(data);
  Serial.print(":");

  Serial.println(crchex);
}

int check_for_receipt(char * crcstring) {
  char receipt[50];
  int charno = 0;

  begin_timeout(2000);
  while( !timeout() && Serial.available() == 0){

  }

  begin_timeout(500);  // if they've already started, .5 sec should be generous
  receipt[charno] = '\0';

  while(Serial.available() > 0 && charno < 49
	&& receipt[charno] != '\r'
	&& receipt[charno] != '\n'
	&& !timeout()){

    charno++;
    receipt[charno - 1] = Serial.read();

    if(receipt[charno - 1] == '\n'){  // end of line
      receipt[charno - 1] = '\0';  // eat that EOL
      break;
    }

    delay(10);  // give time for more characters to come in
  }
  receipt[charno] = '\0';  // make sure we've got a string terminator

  if(charno >= 6) {
    if(receipt[0] == 'R') {  // it's a receipt message
      receipt[6] = '\0';

      if(0 == strcmp(&receipt[2], crcstring)) {
	return 1;
      }
    }
  }

  return 0;
}


int calculate_crc(char * type, char * source_name, char * message) {
  uint16_t crc = 0;

  crc = crc_string(crc, type);
  crc = crc_string(crc, ":");
  crc = crc_string(crc, source_name);
  crc = crc_string(crc, ":");
  crc = crc_string(crc, message);
  crc = crc_string(crc, ":");

  return crc;
}

uint16_t  crc_string(uint16_t crc, char * crc_message) {
  int i;  
  for (i = 0; i < strlen(crc_message) / sizeof crc_message[0]; i++) {
    crc = _crc16_update(crc, crc_message[i]);
  }
  return crc; // must be 0
}

void  empty_input_buffer() {
  byte garbage;
  while(Serial.available() > 0){
    garbage = Serial.read();
  }
  
  return;
}

void begin_timeout(uint16_t timeout_period) {
  wait_start = millis();
  wait_end = wait_start + timeout_period;
  
  return;
}

int timeout() {
  uint16_t now;
  now = millis();
  if(wait_start < wait_end){  // normal case
    if( now > wait_end ){
      return 1;
    }
  } else {   // millis() will wrap
    if( now < wait_start && now > wait_end ){
      return 1;
    }
  }

  return 0;
}

void error(char *msg) {
  Serial.print(source);
  Serial.print(" - ");
  Serial.println(msg);
}


