# SimpleBotCil ESP32 Sketch

Arduino sketch for ESP32 + SSD1306 OLED + FluxGarage RoboEyes.

## Hardware Wiring

### OLED I2C Display (SSD1306)
- **SDA** → GPIO 32
- **SCL** → GPIO 33
- **GND** → GND
- **VCC** → 3.3V

### USB Serial (for communication with macOS app)
- **USB** → USB cable to Mac

## Arduino IDE Setup

1. Install ESP32 board support in Arduino IDE (if not already done):
   - Add `https://dl.espressif.com/dl/package_esp32_index.json` to preferences
   - Select ESP32 Dev Kit board

2. Install required libraries (Sketch → Include Library → Manage Libraries):
   - `Adafruit SSD1306` by Adafruit
   - `FluxGarage_RoboEyes` by Dennis Hoelscher

3. Open `SimpleBotCil.ino` and upload to your ESP32

## Serial Protocol

The sketch listens on Serial (115200 baud) for mood commands:

```
HAPPY\n     → roboEyes.setMood(HAPPY)
TIRED\n     → roboEyes.setMood(TIRED)      (represents sadness)
ANGRY\n     → roboEyes.setMood(ANGRY)      (represents anger)
DEFAULT\n   → roboEyes.setMood(DEFAULT)    (neutral)
NEUTRAL\n   → roboEyes.setMood(DEFAULT)    (alias for DEFAULT)
```

The macOS app (`SimpleBotCil`) will send commands whenever detected emotion changes.

## Debugging

Open the Serial Monitor (115200 baud) to see:
- Initialization messages
- Received commands
- Current mood state

## Mood Mapping

| Mac App | Command | RoboEyes Mood | Display |
|---------|---------|---------------|---------|
| Happy   | HAPPY   | HAPPY         | Smile eyes |
| Sad     | TIRED   | TIRED         | Sleepy/sad eyes |
| Mad     | ANGRY   | ANGRY         | Angry eyes |
| Neutral | DEFAULT | DEFAULT       | Normal eyes |
