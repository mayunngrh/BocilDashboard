/* -------------------------------------------------
   Desk Pet Robot — ESP32-C3 Super Mini
   RoboEyes face + autonomous "drives" behavior engine
   + USB Serial + WiFi (TCP) wireless control
   ---------------------------------------------------
   HARDWARE (confirmed working):
     OLED (I2C, drive as SSD1306) -> SDA GPIO4, SCL GPIO5
     Servo LEFT  (360° cont.)     -> GPIO 10
     Servo RIGHT (360° cont.)     -> GPIO 6
     Capacitive touch sensor      -> GPIO 3
   LIBRARIES: FluxGarage RoboEyes, Adafruit GFX, Adafruit SSD1306, ESP32Servo
   Board: "ESP32C3 Dev Module"

   COMMANDS (from Mac app, via USB Serial or WiFi TCP)
     "ANGRY"   -> enterMode(MODE_ANGRY)
     "HAPPY"   -> enterMode(MODE_HAPPY)
     "SLEEPY"  -> enterMode(MODE_SLEEPY)
     "ASLEEP"  -> enterMode(MODE_ASLEEP)
     "PLAYFUL" -> enterMode(MODE_PLAYFUL)
     "ALERT"   -> enterMode(MODE_ALERT)
     "IDLE"    -> enterMode(MODE_IDLE)

   WIFI: Connects to your WiFi network and prints its IP address
         to Serial on boot. The OLED also briefly shows the IP.
         Mac app connects to that IP on port 4210 (TCP).
-------------------------------------------------*/

#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <FluxGarage_RoboEyes.h>
#include <ESP32Servo.h>
#include <WiFi.h>

/* -------- WIFI -------- */
const char* WIFI_SSID     = "BocilServer";
const char* WIFI_PASSWORD = "1234567890";
const uint16_t TCP_PORT   = 4210;
WiFiServer tcpServer(TCP_PORT);
WiFiClient tcpClient;

/* -------- DISPLAY -------- */
#define SCREEN_WIDTH  128
#define SCREEN_HEIGHT 64
#define OLED_ADDR     0x3C
#define I2C_SDA 4
#define I2C_SCL 5
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);
RoboEyes<Adafruit_SSD1306> roboEyes(display);

/* -------- SERVOS -------- */
#define SERVO_L 10
#define SERVO_R 6
Servo servoL, servoR;
const int   SERVO_STOP = 1500;
const int   LEFT_TRIM  = 0;
const int   RIGHT_TRIM = 0;
const int   SPEED_US   = 220;
const int   LEFT_DIR   = +1;
const int   RIGHT_DIR  = -1;
const float MOTOR_SPEED = 0.60;
const float TURN_SPEED  = 0.60;

/* -------- TOUCH -------- */
#define TOUCH_PIN 3

/* -------- MODES -------- */
#define MODE_IDLE     0
#define MODE_ROAM     1
#define MODE_ALERT    2
#define MODE_HAPPY    3
#define MODE_LOVE     4
#define MODE_ANNOYED  5
#define MODE_ANGRY    6
#define MODE_GRUMPY   7
#define MODE_ATTENTION 8
#define MODE_SLEEPY   9
#define MODE_ASLEEP   10
#define MODE_WAKING   11
#define MODE_STARTLED 12
#define MODE_PLAYFUL  13
#define MODE_DIZZY    14

int mode = MODE_IDLE;
unsigned long modeSince = 0;
unsigned long modeUntil = 0;

/* -------- DRIVES -------- */
float energy    = 80;
float mood      = 55;
float annoyance = 0;
float boredom   = 0;
unsigned long lastTick = 0;
unsigned long lastInteraction = 0;

/* thresholds (tune to taste) */
const float ANNOY_TH      = 40;
const float RAGE_TH       = 75;
const float ENERGY_SLEEPY = 18;
const float BORED_TH      = 70;
const float WAKE_ENERGY   = 90;
const unsigned long MAX_SLEEP_MS = 30000;

/* -------- TAP / GESTURE -------- */
bool touchActive = false;
unsigned long touchStart = 0;
int  tapCount = 0;
unsigned long lastTapTime = 0;
#define TAP_HIST 10
unsigned long tapTimes[TAP_HIST] = {0};
int  tapWrite = 0;
const float TAP_ANNOY = 15;

/* -------- TIMERS -------- */
unsigned long lastMove = 0, moveInterval = 0, roamUntil = 0;
unsigned long nextRoamExcursion = 0, nextQuirk = 0;
unsigned long attnNextHop = 0, angryNextShake = 0, angryNextMove = 0;
unsigned long playNext = 0, nextPlay = 0;
unsigned long dizzyNextConfused = 0;

/* -------- DIZZY -------- */
int spinLoad = 0;
const int DIZZY_THRESHOLD = 12;
unsigned long lastSpinDecay = 0;

/* -------- SERIAL / TCP COMMAND BUFFERS -------- */
String serialBuffer = "";
String tcpBuffer = "";

/* -------- SERVO ACTION SCHEDULER -------- */
enum Act { ACT_STOP, ACT_FWD, ACT_TURNL, ACT_TURNR, ACT_WIGGLE, ACT_SPIN, ACT_BACK, ACT_SHUFFLE,
           ACT_CHARGE, ACT_RSPIN };
Act curAct = ACT_STOP;
unsigned long actUntil = 0, actPhase = 0;
bool actPhaseState = false;

/* -------- FORWARD DECLARATIONS -------- */
void processCommand(String cmd, const char* source);
void enterMode(int m);

/* -------- HELPERS -------- */
float clampf(float v, float lo, float hi){ return v < lo ? lo : (v > hi ? hi : v); }

void drive(float l, float r) {
  int lus = SERVO_STOP + LEFT_TRIM  + (int)(LEFT_DIR  * l * SPEED_US);
  int rus = SERVO_STOP + RIGHT_TRIM + (int)(RIGHT_DIR * r * SPEED_US);
  servoL.writeMicroseconds(constrain(lus, 1000, 2000));
  servoR.writeMicroseconds(constrain(rus, 1000, 2000));
}
void motorStop()    { drive(0, 0); }
void motorForward() { drive(MOTOR_SPEED,  MOTOR_SPEED); }
void rotateCW()     { drive(TURN_SPEED,  -TURN_SPEED); }
void rotateCCW()    { drive(-TURN_SPEED,  TURN_SPEED); }

void startAct(Act a, unsigned long dur) {
  curAct = a; actUntil = millis() + dur; actPhase = millis(); actPhaseState = false;
}

void updateActions() {
  unsigned long now = millis();
  if (curAct != ACT_STOP && actUntil != 0 && now > actUntil) { curAct = ACT_STOP; motorStop(); return; }
  switch (curAct) {
    case ACT_STOP:  motorStop(); break;
    case ACT_FWD:   motorForward(); break;
    case ACT_TURNL: rotateCCW(); break;
    case ACT_TURNR: rotateCW(); break;
    case ACT_BACK:  drive(-MOTOR_SPEED, -MOTOR_SPEED); break;
    case ACT_SPIN:  rotateCW(); break;
    case ACT_CHARGE: drive(1.0, 1.0); break;
    case ACT_RSPIN:  drive(1.0, -1.0); break;
    case ACT_WIGGLE:
      if (now - actPhase > 140) { actPhase = now; actPhaseState = !actPhaseState; }
      actPhaseState ? rotateCW() : rotateCCW(); break;
    case ACT_SHUFFLE:
      if (now - actPhase > 90) { actPhase = now; actPhaseState = !actPhaseState; }
      actPhaseState ? drive(0.85, 0.85) : drive(-0.85, -0.85); break;
  }
}

int tapsInWindow(unsigned long now, unsigned long win) {
  int c = 0;
  for (int i = 0; i < TAP_HIST; i++) if (tapTimes[i] != 0 && now - tapTimes[i] <= win) c++;
  return c;
}

void pokeRegister(unsigned long now) {
  tapTimes[tapWrite] = now; tapWrite = (tapWrite + 1) % TAP_HIST;
  annoyance = clampf(annoyance + TAP_ANNOY, 0, 100);
}

void processCommand(String cmd, const char* source) {
  cmd.trim();
  cmd.toUpperCase();
  if (cmd.length() == 0) return;

  Serial.print("[");
  Serial.print(source);
  Serial.print("] Received: '");
  Serial.print(cmd);
  Serial.println("'");

  if (cmd == "ANGRY")        { Serial.println("  -> enterMode(MODE_ANGRY)"); enterMode(MODE_ANGRY); }
  else if (cmd == "HAPPY")   { Serial.println("  -> enterMode(MODE_HAPPY)"); enterMode(MODE_HAPPY); }
  else if (cmd == "SLEEPY")  { Serial.println("  -> enterMode(MODE_SLEEPY)"); enterMode(MODE_SLEEPY); }
  else if (cmd == "ASLEEP")  { Serial.println("  -> enterMode(MODE_ASLEEP)"); enterMode(MODE_ASLEEP); }
  else if (cmd == "PLAYFUL") { Serial.println("  -> enterMode(MODE_PLAYFUL)"); enterMode(MODE_PLAYFUL); }
  else if (cmd == "ALERT")   { Serial.println("  -> enterMode(MODE_ALERT)"); enterMode(MODE_ALERT); }
  else if (cmd == "IDLE")    { Serial.println("  -> enterMode(MODE_IDLE)"); enterMode(MODE_IDLE); }
  else { Serial.println("  -> Unknown command"); }
}

void updateSerial() {
  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (serialBuffer.length() > 0) {
        processCommand(serialBuffer, "USB");
        serialBuffer = "";
      }
    } else {
      serialBuffer += c;
    }
  }
}

void updateTCP() {
  // If a new client is waiting, take it immediately — don't rely on
  // tcpClient.connected() to notice the old one died first. On the
  // ESP32's LwIP stack, connected() can lag behind an actual peer RST,
  // which left the accept backlog (size ~1) permanently occupied by a
  // stale client and caused every new connection attempt to be reset.
  if (tcpServer.hasClient()) {
    if (tcpClient && tcpClient.connected()) {
      Serial.println("[WiFi] New client waiting, dropping stale one");
      tcpClient.stop();
    }
    tcpClient = tcpServer.available();
    tcpBuffer = "";
    Serial.print("[WiFi] Client connected: ");
    Serial.println(tcpClient.remoteIP());
  }

  if (tcpClient && tcpClient.connected()) {
    while (tcpClient.available() > 0) {
      char c = tcpClient.read();
      if (c == '\n' || c == '\r') {
        if (tcpBuffer.length() > 0) {
          processCommand(tcpBuffer, "WiFi");
          tcpBuffer = "";
        }
      } else {
        tcpBuffer += c;
      }
    }
  }
}

void enterMode(int m) {
  mode = m; modeSince = millis(); modeUntil = 0;
  curAct = ACT_STOP; actUntil = 0; motorStop();

  roboEyes.setHFlicker(false);
  roboEyes.setVFlicker(false);
  roboEyes.setSweat(false);
  roboEyes.setCyclops(false);

  switch (m) {
    case MODE_IDLE:
      roboEyes.setMood(DEFAULT); roboEyes.setCuriosity(false);
      roboEyes.setWidth(36,36); roboEyes.setHeight(36,36);
      roboEyes.setIdleMode(true,3,3); roboEyes.setAutoblinker(true,4,3);
      roboEyes.setPosition(DEFAULT);
      break;
    case MODE_ROAM:
      roboEyes.setMood(DEFAULT); roboEyes.setCuriosity(true);
      roboEyes.setWidth(36,36); roboEyes.setHeight(36,36);
      roboEyes.setIdleMode(true,2,2); roboEyes.setAutoblinker(true,3,3);
      roamUntil = millis() + random(6000,12000); lastMove = 0; moveInterval = 0;
      break;
    case MODE_ALERT:
      roboEyes.setMood(DEFAULT); roboEyes.setIdleMode(false);
      roboEyes.setWidth(40,40); roboEyes.setHeight(40,40);
      roboEyes.setPosition(N); roboEyes.setAutoblinker(true,2,1);
      roboEyes.blink(); startAct(ACT_SHUFFLE,250);
      modeUntil = millis()+1400;
      break;
    case MODE_HAPPY:
      roboEyes.setMood(HAPPY); roboEyes.setIdleMode(false);
      roboEyes.setPosition(DEFAULT); roboEyes.setWidth(36,36); roboEyes.setHeight(36,36);
      roboEyes.setAutoblinker(true,2,1); roboEyes.anim_laugh();
      startAct(ACT_WIGGLE,700);
      break;
    case MODE_LOVE:
      roboEyes.setMood(HAPPY); roboEyes.setIdleMode(false);
      roboEyes.setWidth(38,38); roboEyes.setHeight(16,16);
      roboEyes.setPosition(N); roboEyes.setAutoblinker(true,3,2);
      break;
    case MODE_ANNOYED:
      annoyance = clampf(annoyance-20,0,100);
      roboEyes.setMood(ANGRY); roboEyes.setIdleMode(false);
      roboEyes.setWidth(36,36); roboEyes.setHeight(36,36);
      roboEyes.setPosition(DEFAULT); roboEyes.setSweat(true);
      roboEyes.setHFlicker(true,3); roboEyes.setAutoblinker(true,2,1);
      startAct(ACT_BACK,500);
      modeUntil = millis()+2200;
      break;
    case MODE_ANGRY:
      annoyance = 0; mood = clampf(mood-25,0,100);
      roboEyes.setMood(ANGRY); roboEyes.setIdleMode(false);
      roboEyes.setWidth(38,38); roboEyes.setHeight(38,38);
      roboEyes.setPosition(DEFAULT); roboEyes.setSweat(true);
      roboEyes.setHFlicker(true,5); roboEyes.setAutoblinker(true,2,1);
      roboEyes.anim_confused();
      startAct(ACT_CHARGE,500);
      angryNextShake = millis()+400; angryNextMove = millis()+500;
      modeUntil = millis()+5500;
      break;
    case MODE_GRUMPY:
      roboEyes.setMood(TIRED); roboEyes.setIdleMode(false);
      roboEyes.setWidth(36,36); roboEyes.setHeight(28,28);
      roboEyes.setPosition(SW); roboEyes.setAutoblinker(true,3,2);
      startAct(ACT_TURNR,400);
      modeUntil = millis()+4000;
      break;
    case MODE_ATTENTION:
      roboEyes.setMood(DEFAULT); roboEyes.setCuriosity(true); roboEyes.setIdleMode(false);
      roboEyes.setWidth(38,38); roboEyes.setHeight(40,40);
      roboEyes.setAutoblinker(true,2,1); roboEyes.setPosition(N);
      attnNextHop = millis()+600;
      break;
    case MODE_SLEEPY:
      roboEyes.setMood(TIRED); roboEyes.setIdleMode(false);
      roboEyes.setWidth(36,36); roboEyes.setHeight(22,22);
      roboEyes.setPosition(S); roboEyes.setAutoblinker(true,2,2);
      break;
    case MODE_ASLEEP:
      roboEyes.setMood(TIRED); roboEyes.setIdleMode(false);
      roboEyes.setAutoblinker(false); roboEyes.setPosition(DEFAULT);
      roboEyes.close();
      break;
    case MODE_WAKING:
      roboEyes.setMood(TIRED); roboEyes.setIdleMode(false);
      roboEyes.setAutoblinker(true,2,1);
      roboEyes.setWidth(40,40); roboEyes.setHeight(40,40);
      roboEyes.setPosition(N); roboEyes.open();
      startAct(ACT_SHUFFLE,300); boredom = 30;
      modeUntil = millis()+1600;
      break;
    case MODE_STARTLED:
      roboEyes.setMood(DEFAULT); roboEyes.setIdleMode(false);
      roboEyes.setWidth(44,44); roboEyes.setHeight(44,44);
      roboEyes.open(); roboEyes.setSweat(true);
      roboEyes.setHFlicker(true,4); roboEyes.setAutoblinker(true,1,1);
      startAct(ACT_SHUFFLE,400);
      modeUntil = millis()+1200;
      break;
    case MODE_PLAYFUL:
      roboEyes.setMood(HAPPY); roboEyes.setCuriosity(true); roboEyes.setIdleMode(false);
      roboEyes.setWidth(36,36); roboEyes.setHeight(36,36);
      roboEyes.setAutoblinker(true,2,1); roboEyes.anim_laugh();
      playNext = millis()+300;
      modeUntil = millis()+5000;
      break;
    case MODE_DIZZY:
      roboEyes.setMood(DEFAULT); roboEyes.setIdleMode(false);
      roboEyes.setWidth(36,36); roboEyes.setHeight(36,36);
      roboEyes.setVFlicker(true,3); roboEyes.setAutoblinker(true,2,1);
      roboEyes.anim_confused(); dizzyNextConfused = millis()+700;
      modeUntil = millis()+2600;
      break;
  }
}

void resolveTransient() {
  modeUntil = 0;
  switch (mode) {
    case MODE_STARTLED: enterMode(MODE_ALERT); break;
    case MODE_HAPPY:
    case MODE_LOVE:     enterMode(MODE_ROAM); break;
    case MODE_ANGRY:    enterMode(MODE_GRUMPY); break;
    case MODE_PLAYFUL:  enterMode(MODE_IDLE); nextPlay = millis()+random(15000,30000); break;
    case MODE_ALERT:
    case MODE_ANNOYED:
    case MODE_GRUMPY:
    case MODE_WAKING:
    case MODE_DIZZY:
    default:
      enterMode(MODE_IDLE);
      nextRoamExcursion = millis()+random(6000,14000);
      break;
  }
}

void updateTouch() {
  bool touched = digitalRead(TOUCH_PIN);
  unsigned long now = millis();

  if (touched && !touchActive) {
    touchActive = true; touchStart = now; lastInteraction = now;
    if (mode == MODE_ASLEEP || mode == MODE_SLEEPY) enterMode(MODE_STARTLED);
  }

  if (touched && touchActive) {
    unsigned long held = now - touchStart; lastInteraction = now;
    if (mode != MODE_STARTLED) {
      if (held > 2500)      { if (mode != MODE_LOVE)  enterMode(MODE_LOVE); }
      else if (held > 400)  { if (mode != MODE_HAPPY && mode != MODE_LOVE) enterMode(MODE_HAPPY); }
    }
  }

  if (!touched && touchActive) {
    touchActive = false; lastInteraction = now;
    unsigned long held = now - touchStart;
    if (held < 400) { tapCount++; lastTapTime = now; pokeRegister(now); }
    else if (mode == MODE_HAPPY || mode == MODE_LOVE) modeUntil = now + 1200;
  }
}

void updateDrives() {
  unsigned long now = millis();
  float dt = (now - lastTick) / 1000.0;
  if (dt <= 0) return;
  lastTick = now;
  if (dt > 0.5) dt = 0.5;

  float de = -0.5;
  if      (mode == MODE_ASLEEP) de = 7;
  else if (mode == MODE_SLEEPY) de = 0.5;
  else if (mode == MODE_ROAM || mode == MODE_PLAYFUL || mode == MODE_ANGRY ||
           mode == MODE_ATTENTION || mode == MODE_ANNOYED) de = -3;
  else if (mode == MODE_IDLE) de = -1.0;
  energy = clampf(energy + de*dt, 0, 100);

  annoyance = clampf(annoyance - 6*dt, 0, 100);

  float dm = (50 - mood) * 0.02;
  if (mode == MODE_HAPPY || mode == MODE_LOVE || mode == MODE_PLAYFUL) dm += 8;
  if (mode == MODE_ANGRY || mode == MODE_ANNOYED || mode == MODE_GRUMPY) dm -= 6;
  mood = clampf(mood + dm*dt, 0, 100);

  if (touchActive || (now - lastInteraction) < 2500) boredom = 0;
  else if (mode == MODE_ASLEEP) boredom = 0;
  else boredom = clampf(boredom + 2*dt, 0, 100);
}

void driveRoam(unsigned long now) {
  if (curAct != ACT_STOP) return;
  if (now - lastMove < moveInterval) return;
  lastMove = now; moveInterval = random(1500,3500);
  switch (random(0,5)) {
    case 0: startAct(ACT_FWD,   random(800,1600)); break;
    case 1: startAct(ACT_TURNL, random(300,700)); spinLoad += 2; break;
    case 2: startAct(ACT_TURNR, random(300,700)); spinLoad += 2; break;
    case 3: motorStop(); break;
    case 4: startAct(ACT_SPIN,  random(500,1000)); spinLoad += 3; break;
  }
}

void updateBrain() {
  unsigned long now = millis();

  if (tapCount > 0 && now - lastTapTime > 450) {
    int recent = tapsInWindow(now, 5000);
    if (annoyance >= RAGE_TH || recent >= 8)        enterMode(MODE_ANGRY);
    else if (annoyance >= ANNOY_TH || recent >= 3)  enterMode(MODE_ANNOYED);
    else                                            enterMode(MODE_ALERT);
    tapCount = 0;
  }

  if (modeUntil != 0 && now > modeUntil) resolveTransient();

  if (mode == MODE_ASLEEP) {
    if (energy >= WAKE_ENERGY || (now - modeSince) > MAX_SLEEP_MS) enterMode(MODE_WAKING);
  }
  if (mode == MODE_SLEEPY && (now - modeSince) > 5000) enterMode(MODE_ASLEEP);

  bool freeMode = (mode == MODE_IDLE || mode == MODE_ROAM || mode == MODE_ATTENTION);
  if (freeMode) {
    if (annoyance >= RAGE_TH)               enterMode(MODE_ANGRY);
    else if (annoyance >= ANNOY_TH)         enterMode(MODE_ANNOYED);
    else if (energy <= ENERGY_SLEEPY)       enterMode(MODE_SLEEPY);
    else if (mode != MODE_ATTENTION && boredom >= BORED_TH) enterMode(MODE_ATTENTION);
    else if (mood >= 82 && energy >= 55 && now > nextPlay)  enterMode(MODE_PLAYFUL);
  }

  if (mode == MODE_ANGRY) {
    if (now > angryNextShake) { roboEyes.anim_confused(); angryNextShake = now + 400; }
    if (curAct == ACT_STOP && now > angryNextMove) {
      angryNextMove = now + random(250, 650);
      switch (random(0,4)) {
        case 0: startAct(ACT_CHARGE, random(400,800)); break;
        case 1: startAct(ACT_RSPIN,  random(400,800)); spinLoad += 3; break;
        case 2: startAct(ACT_BACK,   random(300,500)); break;
        case 3: startAct(ACT_SHUFFLE, 300); break;
      }
    }
  }

  if (mode == MODE_ATTENTION) {
    if (now > attnNextHop) {
      attnNextHop = now + random(1200,2500);
      switch (random(0,3)) {
        case 0: startAct(ACT_SHUFFLE,300); break;
        case 1: startAct(ACT_WIGGLE,400);  break;
        case 2: startAct(ACT_SPIN,500); roboEyes.setPosition(random(0,2)?E:W); break;
      }
      roboEyes.blink();
    }
    if ((now - modeSince) > 12000) { boredom = 25; enterMode(MODE_IDLE); }
  }

  if (mode == MODE_PLAYFUL && curAct == ACT_STOP && now > playNext) {
    playNext = now + random(500,1000);
    switch (random(0,3)) {
      case 0: startAct(ACT_SPIN, random(500,900)); spinLoad += 2; break;
      case 1: startAct(ACT_FWD,  random(500,900)); break;
      case 2: startAct(ACT_WIGGLE,500); break;
    }
  }

  if (mode == MODE_DIZZY && now > dizzyNextConfused) {
    roboEyes.anim_confused(); dizzyNextConfused = now + 700;
  }

  if (mode == MODE_IDLE && now > nextRoamExcursion) enterMode(MODE_ROAM);

  if (mode == MODE_IDLE && now > nextQuirk) {
    nextQuirk = now + random(5000,12000);
    switch (random(0,3)) {
      case 0: roboEyes.blink(); break;
      case 1: roboEyes.anim_confused(); break;
      case 2: startAct(ACT_WIGGLE,300); break;
    }
  }

  if (mode == MODE_ROAM) {
    driveRoam(now);
    if (now > roamUntil && curAct == ACT_STOP) {
      enterMode(MODE_IDLE); nextRoamExcursion = now + random(8000,18000);
    }
  }

  if (now - lastSpinDecay > 1000) { lastSpinDecay = now; if (spinLoad > 0) spinLoad--; }
  if (spinLoad >= DIZZY_THRESHOLD && (mode == MODE_ROAM || mode == MODE_PLAYFUL)) {
    spinLoad = 0; enterMode(MODE_DIZZY);
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n\n=========================================================");
  Serial.println("CozmoMini v5 — RoboEyes + USB Serial + WiFi control");
  Serial.println("=========================================================\n");

  Wire.begin(I2C_SDA, I2C_SCL);
  if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR))
    Serial.println("SSD1306 not found");

  pinMode(TOUCH_PIN, INPUT_PULLDOWN);

  ESP32PWM::allocateTimer(0); ESP32PWM::allocateTimer(1);
  servoL.setPeriodHertz(50); servoR.setPeriodHertz(50);
  servoL.attach(SERVO_L,500,2500); servoR.attach(SERVO_R,500,2500);
  motorStop();

  randomSeed(esp_random());
  roboEyes.begin(SCREEN_WIDTH, SCREEN_HEIGHT, 60);
  roboEyes.setBorderradius(8,8);
  roboEyes.setSpacebetween(10);

  /* -------- WIFI SETUP -------- */
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("Connecting WiFi...");
  display.display();

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  delay(100);

  // ESP32-C3 Super Mini fix: the onboard antenna is badly matched, and at
  // default TX power (~20dBm) the radio distorts — the AP hears garbage and
  // auth fails forever (reason 2 loop) even though scanning/RX works fine.
  // Lowering TX power is the standard fix for this exact board.
  WiFi.setTxPower(WIFI_POWER_8_5dBm);

  // Print the exact reason every time the AP kicks us off (core 3.x event API).
  // Reason cheat-sheet: 15/204=wrong password, 2/202=auth fail,
  // 210/211=security mode mismatch (AP wants WPA3-only), 201=AP not found.
  WiFi.onEvent([](WiFiEvent_t event, WiFiEventInfo_t info) {
    Serial.print("\n[WiFi] Disconnect reason: ");
    Serial.println(info.wifi_sta_disconnected.reason);
  }, WiFiEvent_t::ARDUINO_EVENT_WIFI_STA_DISCONNECTED);

  // Accept WPA and up (default threshold can reject WPA2/WPA3-transition hotspots).
  WiFi.setMinSecurity(WIFI_AUTH_WPA_PSK);

  // --- Scan first: prove the ESP32 can actually see networks ---
  Serial.println("[WiFi] Scanning for networks...");
  int n = WiFi.scanNetworks();
  if (n <= 0) {
    Serial.println("[WiFi] No networks found at all! (RF/antenna issue?)");
  } else {
    Serial.print("[WiFi] Found ");
    Serial.print(n);
    Serial.println(" networks:");
    bool foundTarget = false;
    for (int i = 0; i < n; i++) {
      Serial.print("  ");
      Serial.print(WiFi.SSID(i));
      Serial.print("  RSSI:");
      Serial.print(WiFi.RSSI(i));
      Serial.print("  ch:");
      Serial.println(WiFi.channel(i));
      if (WiFi.SSID(i) == String(WIFI_SSID)) foundTarget = true;
    }
    Serial.print("[WiFi] Target '");
    Serial.print(WIFI_SSID);
    Serial.println(foundTarget ? "' WAS found in scan." : "' NOT found in scan!");
  }
  WiFi.scanDelete();

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print("[WiFi] Connecting to ");
  Serial.print(WIFI_SSID);
  unsigned long wifiStart = millis();
  int lastStatus = -1;
  while (WiFi.status() != WL_CONNECTED && millis() - wifiStart < 15000) {
    delay(300);
    int st = WiFi.status();
    if (st != lastStatus) {
      Serial.print("[status:");
      Serial.print(st);
      Serial.print("]");
      lastStatus = st;
    } else {
      Serial.print(".");
    }
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("[WiFi] Connected! IP address: ");
    Serial.println(WiFi.localIP());
    tcpServer.begin();
    Serial.print("[WiFi] TCP command server listening on port ");
    Serial.println(TCP_PORT);

    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("WiFi connected:");
    display.println(WiFi.localIP().toString());
    display.print("Port: ");
    display.println(TCP_PORT);
    display.display();
    delay(2000);
  } else {
    Serial.print("[WiFi] Failed to connect. Status code: ");
    Serial.println(WiFi.status());
    Serial.println("  0=IDLE 1=NO_SSID_AVAIL 3=CONNECTED 4=CONNECT_FAILED 6=DISCONNECTED");
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("WiFi connect failed");
    display.display();
    delay(1500);
  }

  Serial.println("[USB] Listening for serial commands...\n");

  unsigned long now = millis();
  lastTick = now; lastInteraction = now; lastSpinDecay = now;
  nextRoamExcursion = now + random(6000,12000);
  nextQuirk = now + random(5000,10000);
  nextPlay  = now + random(10000,20000);

  enterMode(MODE_IDLE);
}

void loop() {
  updateSerial();
  updateTCP();
  updateTouch();
  updateDrives();
  updateBrain();
  updateActions();
  roboEyes.update();
  delay(10);
}
