# 🚀 Headless MetaTrader 5 (MT5) Deployment on Render

A production-ready, Dockerized setup for running **MetaTrader 5 (MT5)** headlessly on Linux using **Wine** and **Xvfb**, pre-configured for automated broker account login and MQL Expert Advisor (EA) compilation & execution on [Render.com](https://render.com).

---

## 📖 Table of Contents
1. [Overview & Architecture](#-overview--architecture)
2. [How Popups & GUI Dialogs Are Overcome](#-how-popups--gui-dialogs-are-overcome)
3. [How You Will Know It Is Running & Logged In](#-how-you-will-know-it-is-running--logged-in)
4. [Required Environment Variables & Credentials](#-required-environment-variables--credentials)
5. [Step-by-Step Deployment Guide (Render.com)](#-step-by-step-deployment-guide-rendercom)
6. [Included Strategy (`MyCustomEA.mq5`)](#-included-strategy-mycustomeamq5)
7. [Local Testing with Docker](#-local-testing-with-docker)
8. [Monitoring & Troubleshooting](#-monitoring--troubleshooting)

---

## 💡 Overview & Architecture

MetaTrader 5 is natively a Windows desktop application. To run it 24/7 on a cloud host like **Render** without a graphical desktop, this project uses:

- **Ubuntu 22.04 + Wine 64-bit:** Executes MT5 (`terminal64.exe`) and MetaEditor (`metaeditor64.exe`) natively on Linux.
- **Xvfb (X Virtual Framebuffer):** Creates an in-memory virtual display (`DISPLAY=:99`) so MT5 thinks a screen is connected.
- **Automated `entrypoint.sh`:** Handles MQL source code compilation, dynamic configuration generation, login, EA attachment, and log tailing directly to Render's live log viewer.

---

## 🛡️ How Popups & GUI Dialogs Are Overcome

When MT5 is run for the first time, it usually shows popups (Installer Wizard, Login Dialog, Server Picker). In a headless cloud environment, popups can freeze execution if not handled. This setup completely bypasses all popups:

1. **Installer Popups (`mt5setup.exe /auto`):**
   - Handled during Docker build using `xvfb-run wine /tmp/mt5setup.exe /auto`.
   - The `/auto` flag forces silent installation without waiting for user input or GUI button clicks.

2. **First-Time Login Wizard & Account Setup Popups:**
   - Bypassed by passing `/config:C:\startup.ini` when launching `terminal64.exe`.
   - MT5 reads credentials (`Login`, `Password`, `Server`) directly from `startup.ini`, bypassing the GUI login wizard entirely and logging into the broker server automatically on boot.

3. **Wine Dialog Warnings & Crash Windows:**
   - Environment variable `WINEDEBUG=-all` suppresses all Wine system popups, error message boxes, and warning dialogs.

4. **EA Confirmation Popups ("Allow Automated Trading"):**
   - Configured automatically inside `startup.ini` with:
     ```ini
     [Experts]
     AllowLiveTrading=1
     AllowDLL=1
     Enabled=1
     ```
   - This suppresses EA safety popups and enables live trading immediately.

---

## 📡 How You Will Know It Is Running & Logged In

You can verify everything in real-time by viewing the **Live Logs** in your Render Dashboard (**Dashboard ➜ Service ➜ Logs**).

### Expected Log Output Sequence:

#### 1. Container Boot & Compilation (`entrypoint.sh`)
```text
🚀 Starting Headless MetaTrader 5 Container
[1/4] Initializing Xvfb Virtual Display on :99...
✅ Xvfb running on DISPLAY=:99 (PID: 12)
[2/4] Processing Expert Advisor: MyCustomEA.mq5
🛠️ Compiling MQL5 source code: MyCustomEA.mq5...
✅ Compilation successful: MyCustomEA.ex5 generated.
[3/4] Generating MT5 startup.ini configuration...
✅ Generated startup.ini at /root/.wine/drive_c/startup.ini
[4/4] Launching MetaTrader 5 Terminal via Wine...
```

#### 2. MT5 Server Login (`[MT5 Terminal]`)
```text
[MT5 Terminal] MetaTrader 5 x64 build 4410 started
[MT5 Terminal] 11683952: login on VantageInternational-Demo through Access Point #1
[MT5 Terminal] 11683952: authorized on VantageInternational-Demo
[MT5 Terminal] 11683952: automated trading enabled
```

#### 3. EA Trade Execution & Heartbeats (`[MyCustomEA]`)
```text
[MT5 MQL5] [MyCustomEA] Initializing Alternating 1-Min EA on XAUUSD...
[MT5 MQL5] [MyCustomEA] Account #11683952 | Server: VantageInternational-Demo
[MT5 MQL5] [MyCustomEA] Cycle: Placing BUY trade on XAUUSD at Ask: 2500.50 (Lot: 0.01)
[MT5 MQL5] [MyCustomEA] ✅ BUY order executed successfully. Ticket: 987654321
[MT5 MQL5] [MyCustomEA] [Heartbeat] Balance: 10000.00 | Equity: 10000.00 | Open Positions: 1 | Next Action: SELL
```

---

## 🔑 Required Environment Variables & Credentials

The credentials for your Vantage Demo account are pre-configured in `render.yaml` and `Dockerfile`:

| Variable | Configured Value | Description |
| :--- | :--- | :--- |
| `MT5_LOGIN` | `11683952` | Your MT5 Trading Account Number |
| `MT5_PASSWORD` | `#W&$pMG0` | Your MT5 Account Password |
| `MT5_SERVER` | `VantageInternational-Demo` | Vantage Demo Server |
| `EA_NAME` | `MyCustomEA.mq5` | MQL file to compile & execute |
| `CHART_SYMBOL` | `XAUUSD` | Target trading symbol |
| `CHART_TIMEFRAME` | `M1` | 1-Minute chart timeframe |

---

## 🚀 Step-by-Step Deployment Guide (Render.com)

### 1-Click Deployment via Render Blueprint (Recommended)

1. **Push Repository to GitHub / GitLab:**
   Push this project code into your personal GitHub/GitLab repository.

2. **Log into Render:**
   Go to [dashboard.render.com](https://dashboard.render.com).

3. **Create New Blueprint Instance:**
   - Click **New +** top right -> Select **Blueprint**.
   - Connect your GitHub repository.
   - Render automatically detects `render.yaml` and populates `11683952` / `VantageInternational-Demo`.

4. **Deploy:**
   Click **Apply**. Render will build the Docker container and start your 24/7 background worker automatically!

---

## 🤖 Included Strategy (`MyCustomEA.mq5`)

The default EA located in [`mql/MyCustomEA.mq5`](file:///c:/projects/headless-mt5/mql/MyCustomEA.mq5) implements an **alternating 1-minute trade loop on XAUUSD (Gold)**:

- **Minute 1:** Closes any existing open positions and opens a **BUY** order (`0.01` lots).
- **Minute 2:** Closes the Buy order and opens a **SELL** order (`0.01` lots).
- **Minute 3:** Closes the Sell order and opens a **BUY** order... repeating every minute.
- **Heartbeat & Logging:** Emits account balance, equity, and open position state to the logs every 30 seconds.

---

## 🧪 Local Testing with Docker

You can test the container locally on your computer before deploying to Render:

```bash
# 1. Build the Docker image
docker build -t headless-mt5 .

# 2. Run container locally with your demo credentials
docker run --rm -it headless-mt5
```

---

## 🔍 Monitoring & Troubleshooting

### Viewing Live Logs on Render
In your Render Dashboard -> Click your **headless-mt5-worker** service -> Click **Logs**:
- `[MetaEditor]` logs show compilation status of `.mq5` into `.ex5`.
- `[MT5 Terminal]` logs show broker connection, ping, and server authorization status.
- `[MyCustomEA]` logs show position closures, trade entries, order ticket numbers, and periodic heartbeats.
