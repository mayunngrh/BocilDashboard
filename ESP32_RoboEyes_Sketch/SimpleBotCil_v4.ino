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

unsigned long lastMoodChange = 0;
const unsigned long MOOD_INTERVAL = 5000;
int currentMood = 0;
bool appControlled = false;
unsigned long lastSerialCommand = 0;
const unsigned long APP_TIMEOUT = 10000;

String serialBuffer = "";  // Buffer for incoming serial data

void setup() {
  Serial.begin(115200);
  delay(2000);  // Give USB-serial plenty of time to initialize

  Wire.begin(SDA_PIN, SCL_PIN);
  delay(100);

  display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  delay(100);

  eyes.begin(SCREEN_WIDTH, SCREEN_HEIGHT, 60);
  eyes.setAutoblinker(true, 3, 2);
  eyes.setIdleMode(true, 2, 2);
  eyes.setMood(HAPPY);

  Serial.println("\n\n=========================================================");
  Serial.println("SimpleBotCil ESP32 v4 ready!");
  Serial.println("Listening for Mac app commands...");
  Serial.println("=========================================================\n");

  lastMoodChange = millis();
}

void loop() {
  unsigned long currentTime = millis();

  // Read ALL available serial data
  while (Serial.available() > 0) {
    char c = Serial.read();

    if (c == '\n' || c == '\r') {
      // End of command
      if (serialBuffer.length() > 0) {
        processCommand(serialBuffer);
        serialBuffer = "";
      }
    } else if (c >= 32 && c <= 126) {  // Valid ASCII characters
      serialBuffer += c;
    }
  }

  // Check if app has timed out
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
  delay(10);  // Slightly faster loop for better serial responsiveness
}

void processCommand(String command) {
  command.trim();
  command.toUpperCase();

  Serial.print(">>> Received: '");
  Serial.print(command);
  Serial.println("'");

  if (command == "HAPPY") {
    eyes.setMood(HAPPY);
    Serial.println("    -> Set mood: HAPPY");
    appControlled = true;
  } else if (command == "TIRED") {
    eyes.setMood(TIRED);
    Serial.println("    -> Set mood: TIRED (sad)");
    appControlled = true;
  } else if (command == "ANGRY") {
    eyes.setMood(ANGRY);
    Serial.println("    -> Set mood: ANGRY (mad)");
    appControlled = true;
  } else if (command == "DEFAULT") {
    eyes.setMood(DEFAULT);
    Serial.println("    -> Set mood: DEFAULT (neutral)");
    appControlled = true;
  } else if (command == "SLEEP") {
    eyes.close();
    Serial.println("    -> Set mood: SLEEP (eyes closed)");
    appControlled = true;
  } else {
    Serial.println("    -> Unknown command");
  }

  lastSerialCommand = millis();
}

void changeMood() {
  switch (currentMood) {
    case 0:
      eyes.setMood(HAPPY);
      Serial.println("[Auto-cycle] HAPPY");
      currentMood = 1;
      break;
    case 1:
      eyes.setMood(TIRED);
      Serial.println("[Auto-cycle] TIRED (sad)");
      currentMood = 2;
      break;
    case 2:
      eyes.setMood(ANGRY);
      Serial.println("[Auto-cycle] ANGRY");
      currentMood = 0;
      break;
  }
}
