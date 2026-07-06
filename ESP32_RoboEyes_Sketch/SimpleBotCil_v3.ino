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

// Variables for mood cycling
unsigned long lastMoodChange = 0;
const unsigned long MOOD_INTERVAL = 5000;  // 5 seconds
int currentMood = 0;  // 0 = happy, 1 = sad (tired), 2 = angry
bool appControlled = false;  // true if receiving commands from Mac app
unsigned long lastSerialCommand = 0;
const unsigned long APP_TIMEOUT = 10000;  // Return to auto-cycle if no command for 10 seconds

void setup() {
  Serial.begin(115200);
  delay(1000);

  Wire.begin(SDA_PIN, SCL_PIN);
  delay(100);

  display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  delay(100);

  eyes.begin(SCREEN_WIDTH, SCREEN_HEIGHT, 60);
  eyes.setAutoblinker(true, 3, 2);
  eyes.setIdleMode(true, 2, 2);
  eyes.setMood(HAPPY);

  Serial.println("\n\nSimpleBotCil ESP32 ready!");
  Serial.println("Auto-cycling moods every 5 seconds...");
  Serial.println("Waiting for commands from Mac app (HAPPY, TIRED, ANGRY, DEFAULT)");
  Serial.println("=========================================================");

  lastMoodChange = millis();
}

void loop() {
  unsigned long currentTime = millis();

  // PRIORITY: Check if Mac app sent a command
  while (Serial.available() > 0) {
    String command = Serial.readStringUntil('\n');
    command.trim();
    command.toUpperCase();

    if (command.length() > 0) {
      Serial.print("Received: ");
      Serial.println(command);

      if (command == "HAPPY") {
        eyes.setMood(HAPPY);
        Serial.println("-> Set to HAPPY");
        appControlled = true;
      } else if (command == "TIRED") {
        eyes.setMood(TIRED);
        Serial.println("-> Set to TIRED (sad)");
        appControlled = true;
      } else if (command == "ANGRY") {
        eyes.setMood(ANGRY);
        Serial.println("-> Set to ANGRY (mad)");
        appControlled = true;
      } else if (command == "DEFAULT") {
        eyes.setMood(DEFAULT);
        Serial.println("-> Set to DEFAULT (neutral)");
        appControlled = true;
      }

      lastSerialCommand = currentTime;
    }
  }

  // Check if app has timed out (return to auto-cycle if no command for 10 seconds)
  if (appControlled && (currentTime - lastSerialCommand >= APP_TIMEOUT)) {
    appControlled = false;
    Serial.println(">>> App timeout - returning to auto-cycle mode");
    lastMoodChange = currentTime;
  }

  // Auto-cycle moods only if NOT controlled by app
  if (!appControlled) {
    if (currentTime - lastMoodChange >= MOOD_INTERVAL) {
      changeMood();
      lastMoodChange = currentTime;
    }
  }

  eyes.update();
  delay(20);  // ~50 FPS
}

void changeMood() {
  switch (currentMood) {
    case 0:  // Happy
      eyes.setMood(HAPPY);
      Serial.println("[Auto] HAPPY");
      currentMood = 1;
      break;
    case 1:  // Sad (using TIRED)
      eyes.setMood(TIRED);
      Serial.println("[Auto] TIRED (sad)");
      currentMood = 2;
      break;
    case 2:  // Angry
      eyes.setMood(ANGRY);
      Serial.println("[Auto] ANGRY");
      currentMood = 0;
      break;
  }
}
