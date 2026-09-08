#!/bin/bash
set -e

echo "=================================================="
echo "🚀 Starting Headless MetaTrader 5 Container"
echo "=================================================="

# 1. Initialize Virtual Display (Xvfb)
echo "[1/4] Initializing Xvfb Virtual Display on :99..."
rm -f /tmp/.X99-lock
Xvfb :99 -screen 0 1024x768x16 &
XVFB_PID=$!
sleep 2

export DISPLAY=:99

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

mkdir -p "${EXPERTS_DIR}"
mkdir -p "${LOGS_DIR}"
mkdir -p "${TERMINAL_LOGS_DIR}"

# 2. MQL File Handling & Compilation
EA_NAME="${EA_NAME:-MyCustomEA.mq5}"
SOURCE_EA_PATH="/app/mql/${EA_NAME}"
TARGET_EA_PATH="${EXPERTS_DIR}/${EA_NAME}"

echo "[2/4] Processing Expert Advisor: ${EA_NAME}"

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

# 3. Generate MT5 startup.ini Config File
echo "[3/4] Generating MT5 startup.ini configuration..."

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
cat "${CONFIG_FILE}" | sed 's/Password=.*/Password=********/'

# 4. Launch MT5 Terminal & Stream Logs to Container stdout
echo "[4/4] Launching MetaTrader 5 Terminal via Wine..."

TERMINAL_PATH="${MT5_DIR}/terminal64.exe"

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
