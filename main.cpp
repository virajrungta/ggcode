#include <DHT.h>

// -------- Pins --------
#define SOIL_PIN1 32
#define SOIL_PIN2 34
#define WATER_PIN 35
#define DHT_PIN 33
#define DHT_TYPE DHT11

// -------- Objects --------
DHT dht(DHT_PIN, DHT_TYPE);

// -------- Calibration --------
const int dryValue = 3000;  // adjust after testing dry soil
const int wetValue = 1500;  // adjust after testing wet soil

void setup() {
  Serial.begin(115200);
  delay(1000);
  dht.begin();
  pinMode(WATER_PIN, INPUT);
}

int soilPercent(int rawValue) {
  int percent = map(rawValue, dryValue, wetValue, 0, 100);
  if (percent > 100) percent = 100;
  if (percent < 0) percent = 0;
  return percent;
}

void loop() {
  // Soil readings
  int soilRaw1 = analogRead(SOIL_PIN1);
  int soilRaw2 = analogRead(SOIL_PIN2);

  int soilPerc1 = soilPercent(soilRaw1);
  int soilPerc2 = soilPercent(soilRaw2);

  // Water level
  int waterState = digitalRead(WATER_PIN);

  // DHT11
  float humidity = dht.readHumidity();
  float temperature = dht.readTemperature();

  // Print
  Serial.print("Soil 1: ");
  Serial.print(soilPerc1); 
  Serial.print("% | Soil 2: ");
  Serial.print(soilPerc2); 
  Serial.print("% | Water Level: ");
  Serial.print(waterState == HIGH ? "Water detected" : "No water");

  if (isnan(humidity) || isnan(temperature)) {
    Serial.println(" | DHT read failed!");
  } else {
    Serial.print(" | Temp: ");
    Serial.print(temperature);
    Serial.print(" C  Humidity: ");
    Serial.println(humidity);
    Serial.println(" %");
  }

  delay(2000);
}
