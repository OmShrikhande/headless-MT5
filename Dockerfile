FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV WINEPREFIX=/root/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all
ENV DISPLAY=:99

# Install system dependencies & Wine
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        wine64 \
        wine32 \
        wine \
        winetricks \
        xvfb \
        x11-utils \
        curl \
        wget \
        cabextract \
        gnupg \
        ca-certificates \
        procps \
        psmisc \
        net-tools \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Initialize Wine environment and download MT5 installer
RUN xvfb-run wineboot --init && \
    wget https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe -O /tmp/mt5setup.exe && \
    xvfb-run wine /tmp/mt5setup.exe /auto && \
    sleep 5 && \
    rm -f /tmp/mt5setup.exe

# Ensure MQL5 Experts and Logs directories exist
RUN mkdir -p "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts" && \
    mkdir -p "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Logs" && \
    mkdir -p "/root/.wine/drive_c/Program Files/MetaTrader 5/logs"

# Copy local project files
COPY mql /app/mql
COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/entrypoint.sh

# Environment Variable Defaults
ENV MT5_LOGIN="11683952"
ENV MT5_PASSWORD="#W&$pMG0"
ENV MT5_SERVER="VantageInternational-Demo"
ENV EA_NAME="MyCustomEA.mq5"
ENV CHART_SYMBOL="XAUUSD"
ENV CHART_TIMEFRAME="M1"

ENTRYPOINT ["/app/entrypoint.sh"]
