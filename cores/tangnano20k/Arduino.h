#pragma once

#include <stdint.h>
#include "api/ArduinoAPI.h"
#include "api/HardwareSerial.h"
#include "tangnano20k_soc.h"
#include "pins_arduino.h"
#include "TangNanoI2S.h"

using namespace arduino;

/* Global Serial instance, defined in HardwareSerial.cpp */
extern arduino::HardwareSerial &Serial;

/* Global I2S instance (audio out to the onboard MAX98357A), defined in
 * TangNanoI2S.cpp */
extern tangnano20k::TangNanoI2S I2S;
