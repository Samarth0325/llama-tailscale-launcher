#!/bin/bash

TAILSCALE_DOWNLOAD="https://tailscale.com/"
LLAMA_DIR="$HOME/llama.cpp"
MODEL_PATH="$HOME/llama.cpp/models/Qwen2.5-0.5B-Instruct-Q4_K_M_Samarth.gguf"
MODEL_DIR="$LLAMA_DIR/models"
PID_FILE="$HOME/llama.cpp/.llama-server.pid"
PORT=8080
LOG_FILE="$HOME/llama.cpp/llama.log"
LLAMA_CPP="https://github.com/ggml-org/llama.cpp"
LLAMA_SERVER_MODEL="https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
HFP_AI="https://ai.nomineelife.com/"



# =========================
# FUNCTIONS
# =========================

install_dependencies() {
    echo "🔧 Checking dependencies..."
    sudo apt update -y
    sudo apt install -y build-essential cmake git wget curl lsof netcat-openbsd
}

install_tailscale() {
    if ! command -v tailscale &> /dev/null; then
        echo "🔧 Installing Tailscale..."
        curl -fsSL "$TAILSCALE_DOWNLOAD"install.sh | sh
    else
        echo "✅ Tailscale already installed"
    fi

    if tailscale status 2>/dev/null | grep -q "$USER"; then
        echo "✅ Tailscale permissions already configured"
    else
        echo "🔐 Authentication required..."

        # GUI prompt instead of terminal
        pkexec tailscale set --operator=$USER
    fi
}

connect_tailscale() {
    STATE=$(tailscale status --json 2>/dev/null | grep '"BackendState"' | cut -d '"' -f4)

    if [ "$STATE" != "Running" ]; then
        echo "🔗 Connecting to NomineeLife network..."

        sudo tailscale up \
          --login-server https://ai.nomineelife.com:8443 \
          --accept-routes \
          --reset
    else
        echo "✅ Already connected to network"
    fi
}

setup_llama() {
    if [ ! -d "$LLAMA_DIR" ]; then
        echo "📦 Cloning llama.cpp..."
        git clone "$LLAMA_CPP" "$LLAMA_DIR"
    else
        echo "✅ llama.cpp already exists"
    fi

    cd "$LLAMA_DIR" || exit

    if [ ! -f "./build/bin/llama-server" ]; then
        echo "⚙️ Building llama.cpp..."
        make
    else
        echo "✅ llama-server already built"
    fi
}

download_model() {
    # ✅ ONLY for new users
   if [ -f "$MODEL_PATH" ]; then
    echo "✅ Model found → skipping download"
else
    echo "⬇️ Model not found → downloading..."
    mkdir -p "$LLAMA_DIR/models"
    wget -c -P "$LLAMA_DIR/models" \
    "$LLAMA_SERVER_MODEL"
fi
}

start_server() {
    TS_IP=$(tailscale ip -4)
    echo "📡 Node IP: $TS_IP"

    cd "$LLAMA_DIR" || exit

    if lsof -i :$PORT > /dev/null; then
        echo "⚠️ Port $PORT in use. Killing..."
        fuser -k $PORT/tcp
    fi

    echo "🧠 Starting llama-server..."
    ./build/bin/llama-server \
        -m "$MODEL_PATH" \
        --host 0.0.0.0 \
        --port $PORT > "$LOG_FILE" 2>&1 &

    echo $! > "$PID_FILE"

    echo "⏳ Waiting for server..."
    SERVER_UP=false

    for i in {1..20}; do
        if nc -z localhost $PORT; then
            SERVER_UP=true
            echo "✅ Server is up"
            break
        fi
        sleep 1
    done

    if [ "$SERVER_UP" = false ]; then
        echo "❌ Server failed. Logs:"
        tail -n 10 "$LOG_FILE"
        exit 1
    fi

    URL="$HFP_AI"

    echo ""
    echo "🚀 NODE LIVE → $URL"
    echo ""

    xdg-open "$URL" 2>/dev/null || open "$URL" 2>/dev/null
}

stop_server() {
    echo "🛑 Stopping NomineeLife Node..."

    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE") 2>/dev/null
        rm -f "$PID_FILE"
        echo "✅ LLaMA server stopped"
    else
        echo "⚠️ No running server found"
    fi

    tailscale down
    echo "🔌 Tailscale disconnected"
}

# =========================
# AUTO TOGGLE
# =========================

if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
    echo "🔌 Node is running → stopping..."
    stop_server
else
    echo "🚀 Node is stopped → starting..."
    install_dependencies
    install_tailscale
    connect_tailscale
    setup_llama
    download_model
    start_server
fi
