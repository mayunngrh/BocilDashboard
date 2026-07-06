#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <FluxGarage_RoboEyes.h>

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1

#define SDA_PIN 32
#define SCL_PIN 33

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
RoboEyes eyes(display);

unsigned long lastMoodChangeTime = 0;
const unsigned long MOOD_CHANGE_INTERVAL = 5000;  // 5 seconds
int currentMoodIndex = 0;
int moods[] = {DEFAULT, HAPPY, TIRED, ANGRY};
int moodCount = 4;

void setup() {
  Serial.begin(115200);
  delay(500);

  Wire.begin(SDA_PIN, SCL_PIN);
  delay(100);

  display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  delay(100);

  eyes.begin(SCREEN_WIDTH, SCREEN_HEIGHT, 60);
  eyes.setAutoblinker(true, 3, 2);
  eyes.setIdleMode(true, 2, 2);
  eyes.setMood(DEFAULT);

  lastMoodChangeTime = millis();
  Serial.println("SimpleBotCil ready. Changing moods every 5 seconds...");
}

void changeMood() {
  eyes.setMood(moods[currentMoodIndex]);

  String moodName;
  switch (moods[currentMoodIndex]) {
    case DEFAULT:
      moodName = "DEFAULT (neutral)";
      break;
    case HAPPY:
      moodName = "HAPPY";
      break;
    case TIRED:
      moodName = "TIRED (sad)";
      break;
    case ANGRY:
      moodName = "ANGRY (mad)";
      break;
  }

  Serial.print("Mood changed to: ");
  Serial.println(moodName);

  currentMoodIndex = (currentMoodIndex + 1) % moodCount;
}

void loop() {
  unsigned long currentTime = millis();

  if (currentTime - lastMoodChangeTime >= MOOD_CHANGE_INTERVAL) {
    changeMood();
    lastMoodChangeTime = currentTime;
  }

  eyes.update();
  delay(20);
}
