// http://code.google.com/p/max6675-arduino-library/
#include <MAX6675.h>

int SO = 13;              // SO pin of MAX6675
int CS = 12;              // CS pin on MAX6675
int SCK = 11;             // SCK pin of MAX6675
int units = 0;            // Units to readout temp (0 = ˚F, 1 = ˚C)
float max6675_error = 0.0;        // Temperature compensation error
float temperature = 0.0;

// Initialize the MAX6675 Library

MAX6675 temp0(CS, SO, SCK, units, max6675_error);

#include <LiquidCrystal.h>
//create object to control an LCD.  
//  (RS, Enable, d4-d7)
LiquidCrystal lcd(6, 5, 7, 8, 9, 10);


//  how do we identify ourselves to the logging application?
#define source "ghetto sous vide"



// what temperature are we trying to keep the food at?
int setpoint = 120;

// pins for controlling setpoin
#define UP_PIN   3
#define DOWN_PIN 2


// pin for controlling the cooker
// HIGH is on, LOW is off
#define COOKER_PIN 4


void setup(void) {
  lcd.begin(16,2);

  // initialize inputs/outputs
  // start serial port
  Serial.begin(9600);

  error("booting");


  // temperature control pins
  init_button(UP_PIN);
  init_button(DOWN_PIN);

  // cooker control
  pinMode(COOKER_PIN, OUTPUT);

  delay(100);
}

int loop_count = 0;
void loop(void) {
  adjust_setpoint();

  temperature = temp0.read_temp(5);
  Serial.println((int)temperature);

  // if reading is outside range (probably DEVICE_DISCONNECTED) don't log it
  if (temperature > -67) {

    lcd.clear();
    lcd.setCursor(0,0);   // technically redundant, but clarifies things
    lcd.print("set:");
    lcd.setCursor(0,1);
    lcd.print("current:");
    lcd.setCursor(10,0);
    lcd.print(setpoint);
    lcd.setCursor(10,1);
    lcd.print((int)temperature);

    control_relay(COOKER_PIN, (int)temperature, setpoint);
  }

  loop_count++;
  delay(200);
}

// how many readings since last change?  don't want to toggle relay too quickly
void control_relay(int pin, int temperature, int setpoint) {
  int ideal_pin = LOW;
  if(temperature < setpoint) {
    ideal_pin = HIGH;
  } else {
    ideal_pin = LOW;
  }

  if(time_to_change(ideal_pin)){
    digitalWrite(pin, ideal_pin);
  }
}

int count_at_last_change = 0;
int prev_setting = LOW;
bool time_to_change(int ideal_pin) {

  if (ideal_pin == prev_setting) {
    return false;
  }

  if (((loop_count - count_at_last_change) > 25) ||  // 5 seconds
      (loop_count < count_at_last_change)) { // we wrapped around
    count_at_last_change = loop_count;
    prev_setting = ideal_pin;

    return true;
  }
  
}

void adjust_setpoint() {
  if(button_pressed(UP_PIN)) {
    setpoint++;
  }

  if(button_pressed(DOWN_PIN)) {
    setpoint--;
  }
}

void init_button(int button) {
  pinMode(button, INPUT);
  digitalWrite(button, HIGH);
}

bool button_pressed(int button) {
  if (digitalRead(button) == LOW) {
    return true;
  } else {
    return false;
  }
}


void error(char *msg) {
  Serial.print(source);
  Serial.print(" - ");
  Serial.println(msg);
}


