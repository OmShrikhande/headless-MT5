#!/bin/bash
set -e

echo "=================================================="
echo "🚀 Starting Headless MetaTrader 5 Container"
echo "=================================================="

# 1. Initialize Virtual Display (Xvfb)
echo "[1/5] Initializing Xvfb Virtual Display on :99..."
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
Xvfb :99 -screen 0 1024x768x16 &
XVFB_PID=$!
sleep 2

export DISPLAY=:99
export WINEPREFIX="${WINEPREFIX:-/root/.wine}"
export WINEARCH="${WINEARCH:-win64}"
export WINEDEBUG="${WINEDEBUG:--all}"

if ! ps -p $XVFB_PID > /dev/null; then
    echo "❌ Failed to start Xvfb process"
    exit 1
fi
echo "✅ Xvfb running on DISPLAY=:99 (PID: $XVFB_PID)"

# MT5 Directory Paths inside Wine Prefix
MT5_DIR="/root/.wine/drive_c/Program Files/MetaTrader 5"
EXPERTS_DIR="${MT5_DIR}/MQL5/Experts"
LOGS_DIR="${MT5_DIR}/MQL5/Logs"
TERMINAL_LOGS_DIR="${MT5_DIR}/logs"
TERMINAL_PATH="${MT5_DIR}/terminal64.exe"

install_mt5() {
    echo "📦 Installing MetaTrader 5 via Wine (silent)..."
    wineboot --init || true
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f || true

    local setup="/opt/mt5setup.exe"
    if [ ! -f "${setup}" ]; then
        echo "⬇️ Downloading mt5setup.exe..."
        wget -O /tmp/mt5setup.exe \
          https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe
        setup="/tmp/mt5setup.exe"
    fi

    # Installer is a downloader stub; exit code is often non-zero even on success
    wine "${setup}" /auto &
    local install_pid=$!

    echo "⏳ Waiting for terminal64.exe (up to ~20 minutes)..."
    for i in $(seq 1 120); do
        if [ -f "${TERMINAL_PATH}" ]; then
            echo "✅ MT5 installed: ${TERMINAL_PATH}"
            wait "${install_pid}" || true
            return 0
        fi
        # Still running?
        if ! kill -0 "${install_pid}" 2>/dev/null; then
            wait "${install_pid}" || true
            # Give filesystem a moment after process exit
            sleep 3
            if [ -f "${TERMINAL_PATH}" ]; then
                echo "✅ MT5 installed after installer exit"
                return 0
            fi
            echo "⚠️ Installer exited before terminal64.exe appeared (attempt checkpoint ${i})"
            # One retry
            wine "${setup}" /auto &
            install_pid=$!
        fi
        sleep 10
    done

    wait "${install_pid}" || true
    return 1
}

# 2. Ensure MT5 is installed
echo "[2/5] Checking MetaTrader 5 installation..."
if [ ! -f "${TERMINAL_PATH}" ]; then
    if ! install_mt5; then
        echo "❌ Failed to install MetaTrader 5"
        echo "   On Apple Silicon, QEMU emulation of Wine/MT5 is often broken."
        echo "   Deploy to Render (native linux/amd64) or build on an amd64 machine."
        exit 1
    fi
else
    echo "✅ MT5 already present at ${TERMINAL_PATH}"
fi

mkdir -p "${EXPERTS_DIR}"
mkdir -p "${LOGS_DIR}"
mkdir -p "${TERMINAL_LOGS_DIR}"

# 3. MQL File Handling & Compilation
EA_NAME="${EA_NAME:-MyCustomEA.mq5}"
SOURCE_EA_PATH="/app/mql/${EA_NAME}"
TARGET_EA_PATH="${EXPERTS_DIR}/${EA_NAME}"

echo "[3/5] Processing Expert Advisor: ${EA_NAME}"

if [ ! -f "${SOURCE_EA_PATH}" ]; then
    echo "⚠️ Warning: ${SOURCE_EA_PATH} not found in /app/mql!"
else
    echo "📄 Copying ${EA_NAME} to MT5 Experts directory..."
    cp -f "${SOURCE_EA_PATH}" "${TARGET_EA_PATH}"
fi

EA_COMPILED_NAME="${EA_NAME}"

# Auto-compilation for .mq5 source files
if [[ "${EA_NAME}" == *.mq5 ]]; then
    echo "🛠️ Compiling MQL5 source code: ${EA_NAME}..."
    METAEDITOR_PATH="${MT5_DIR}/metaeditor64.exe"
    
    if [ -f "${METAEDITOR_PATH}" ]; then
        COMPILE_LOG_WIN="C:\\compile.log"
        COMPILE_LOG_LINUX="/root/.wine/drive_c/compile.log"
        rm -f "${COMPILE_LOG_LINUX}"
        
        wine "${METAEDITOR_PATH}" /compile:"C:\\Program Files\\MetaTrader 5\\MQL5\\Experts\\${EA_NAME}" /log:"${COMPILE_LOG_WIN}" || true
        
        if [ -f "${COMPILE_LOG_LINUX}" ]; then
            echo "--- MetaEditor Compilation Log ---"
            cat "${COMPILE_LOG_LINUX}"
            echo "----------------------------------"
        fi
        
        EX5_NAME="${EA_NAME%.mq5}.ex5"
        if [ -f "${EXPERTS_DIR}/${EX5_NAME}" ]; then
            echo "✅ Compilation successful: ${EX5_NAME} generated."
            EA_COMPILED_NAME="${EX5_NAME}"
        else
            echo "⚠️ Compilation completed. Using ${EA_NAME} in config."
        fi
    else
        echo "⚠️ metaeditor64.exe not found at ${METAEDITOR_PATH}. Skipping compilation."
    fi
fi

# 4. Generate MT5 startup.ini Config File
echo "[4/5] Generating MT5 startup.ini configuration..."

# Default password set here (not Dockerfile ENV) so "$" is not eaten by Docker
: "${MT5_PASSWORD:=#W&\$pMG0}"

if [ -z "${MT5_LOGIN}" ] || [ -z "${MT5_PASSWORD}" ] || [ -z "${MT5_SERVER}" ]; then
    echo "❌ MT5_LOGIN, MT5_PASSWORD, and MT5_SERVER must be set"
    exit 1
fi

CONFIG_FILE="/root/.wine/drive_c/startup.ini"
cat <<EOF > "${CONFIG_FILE}"
[Common]
Login=${MT5_LOGIN}
Password=${MT5_PASSWORD}
Server=${MT5_SERVER}
EnableNews=0
CertStoreAutoSave=1

[Experts]
AllowLiveTrading=1
AllowDLL=1
Enabled=1

[Startup]
Expert=${EA_COMPILED_NAME}
Symbol=${CHART_SYMBOL:-EURUSD}
Period=${CHART_TIMEFRAME:-M15}
EOF

echo "✅ Generated startup.ini at ${CONFIG_FILE}:"
sed 's/Password=.*/Password=********/' "${CONFIG_FILE}"

# 5. Launch MT5 Terminal & Stream Logs to Container stdout
echo "[5/5] Launching MetaTrader 5 Terminal via Wine..."

if [ ! -f "${TERMINAL_PATH}" ]; then
    echo "❌ Terminal executable not found at ${TERMINAL_PATH}"
    exit 1
fi

# Background process to tail log files to container stdout
(
    while true; do
        sleep 5
        LATEST_TERM_LOG=$(ls -t "${TERMINAL_LOGS_DIR}"/*.log 2>/dev/null | head -n 1)
        if [ -n "${LATEST_TERM_LOG}" ]; then
            tail -n 50 -f "${LATEST_TERM_LOG}" 2>/dev/null | sed 's/^/[MT5 Terminal] /' &
            break
        fi
    done
) &

(
    while true; do
        sleep 5
        LATEST_MQL_LOG=$(ls -t "${LOGS_DIR}"/*.log 2>/dev/null | head -n 1)
        if [ -n "${LATEST_MQL_LOG}" ]; then
            tail -n 50 -f "${LATEST_MQL_LOG}" 2>/dev/null | sed 's/^/[MT5 MQL5] /' &
            break
        fi
    done
) &

echo "🏃 Running terminal64.exe with config /config:C:\\startup.ini"
exec wine "${TERMINAL_PATH}" /config:"C:\\startup.ini"
