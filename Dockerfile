FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV WINEPREFIX=/root/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all
ENV DISPLAY=:99

# Install system dependencies & Wine.
# NOTE: Wine is intentionally NOT initialized during image build.
# Running wine/mt5setup under QEMU (Apple Silicon -> amd64) is unreliable;
# MT5 is installed on first container start (works on Render's native amd64).
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        wine64 \
        wine32 \
        wine \
        winetricks \
        winbind \
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

WORKDIR /app

# Prefetch the MT5 installer so first boot does not depend on CDN availability alone
RUN wget -O /opt/mt5setup.exe \
      https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe

# Copy local project files
COPY mql /app/mql
COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/entrypoint.sh

# Environment Variable Defaults
# Do NOT put passwords containing "$" in ENV — Docker expands $vars and mangles them.
# Defaults for MT5_PASSWORD live in entrypoint.sh / render.yaml instead.
ENV MT5_LOGIN="11683952"
ENV MT5_SERVER="VantageInternational-Demo"
ENV EA_NAME="MyCustomEA.mq5"
ENV CHART_SYMBOL="XAUUSD"
ENV CHART_TIMEFRAME="M1"

ENTRYPOINT ["/app/entrypoint.sh"]
