#!/bin/bash

if [ -z "$INSTALL_DIR" ]; then
  echo "Error: Variable INSTALL_DIR is not set. This sub-script must be called by installer.sh"
  exit 1
fi

echo === CONSOLE BACKEND SETUP ===
# Create backend/terminal-server.js
mkdir -p $INSTALL_DIR/backend
cat > $INSTALL_DIR/backend/terminal-server.js <<'EOF_BACKENDTERMINALSERVER'
const WebSocket = require('ws');
const Docker = require('dockerode');
const docker = new Docker();

const sessions = new Map();
const TIMEOUT = 5 * 60 * 1000; // 5 min

function resetTimeout(session) {
  clearTimeout(session.timeout);
  session.timeout = setTimeout(() => {
    if (session.ws.length === 0) {
      session.container.kill();
      sessions.delete(session.id);
    }
  }, TIMEOUT);
}

const wss = new WebSocket.Server({ port: 3000 });
console.log('Terminal server on port 3000');

wss.on('connection', async (ws, req) => {
  const urlParams = new URLSearchParams(req.url.slice(4));
  const sessionId = urlParams.get('session');
  let session = sessions.get(sessionId);
  let isNewSession = false;

  if (!session) {
    isNewSession = true;
    session = {
      id: `session-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      ws: [],
      container: null,
      lastActivity: Date.now(),
      timeout: null
    };
    sessions.set(session.id, session);

    try {
      const container = await docker.createContainer({
        Image: 'photon-builder',
        Tty: true,
        AttachStdin: true,
        AttachStdout: true,
        AttachStderr: true,
        Env: ['TERM=xterm-256color'],
        HostConfig: { Memory: 536870912, NanoCpus: 1000000000 } // 512MB, 1 CPU
      });
      session.container = container;
      await container.start();

      // Create tmux session with default shell and explicit TERM
      const execNew = await container.exec({
        Cmd: ['tmux', 'new-session', '-d', '-s', session.id, '-e', 'TERM=xterm-256color'],
        Env: ['TERM=xterm-256color'],
        AttachStdin: false,
        AttachStdout: false,
        AttachStderr: false,
      });
      await execNew.start();

      // Wait briefly for session to initialize
      await new Promise(resolve => setTimeout(resolve, 500));

      // Disable status bar to prevent leak into stream
      try {
        const execStatusOff = await container.exec({
          Cmd: ['tmux', 'set-option', '-gq', 'status', 'off'],
          AttachStdin: false,
          AttachStdout: false,
          AttachStderr: false,
        });
        await execStatusOff.start({ Detach: true });

        const execWindowStatusOff = await container.exec({
          Cmd: ['tmux', 'set-window-option', '-gq', '-t', session.id, 'status', 'off'],
          AttachStdin: false,
          AttachStdout: false,
          AttachStderr: false,
        });
        await execWindowStatusOff.start({ Detach: true });
      } catch (err) {
        console.log('Failed to disable tmux status bar:', err.message);
      }
    } catch (err) {
      ws.send(`Error: ${err.message}`);
      ws.close();
      return;
    }
  }

  try {
    // Attach to tmux session
    const execAttach = await session.container.exec({
      Cmd: ['tmux', 'attach-session', '-t', session.id],
      Env: ['TERM=xterm-256color'],
      AttachStdin: true,
      AttachStdout: true,
      AttachStderr: true,
      Tty: true
    });
    const stream = await execAttach.start({ hijack: true, stdin: true });
    session.ws.push({ ws, stream });

    stream.on('data', (chunk) => {
      const data = chunk.toString();
      session.ws.forEach(client => {
        if (client.ws.readyState === WebSocket.OPEN) client.ws.send(data);
      });
    });

    ws.on('message', (message) => {
      stream.write(message);
      session.lastActivity = Date.now();
      resetTimeout(session);
    });

    ws.on('close', () => {
      const client = session.ws.find(client => client.ws === ws);
      if (client) {
        client.stream.write('\x02d');
        setTimeout(() => {
          client.stream.end();
        }, 100); // Delay to allow detach to process
        session.ws = session.ws.filter(c => c !== client);
      }
      if (session.ws.length === 0) {
        resetTimeout(session);
      }
    });

    if (isNewSession) {
      ws.send(JSON.stringify({ type: 'session', id: session.id }));
    } else {
      // Send current pane content for re-attach (clean from top, no status)
      const execCapture = await session.container.exec({
        Cmd: ['tmux', 'capture-pane', '-t', session.id, '-p', '-S', '-'],
        Env: ['TERM=xterm-256color'],
        AttachStdout: true,
        AttachStderr: false
      });
      const captureStream = await execCapture.start({ hijack: false });
      let buffer = '';
      captureStream.on('data', chunk => buffer += chunk.toString());
      captureStream.on('end', () => {
        ws.send(buffer + '\r\n');  // Ensure clean line after buffer
      });
    }
    resetTimeout(session);
  } catch (err) {
    ws.send(`Error: ${err.message}`);
    ws.close();
  }
});
EOF_BACKENDTERMINALSERVER

# Install backend dependencies
cd $INSTALL_DIR/backend
npm init -y
npm install ws dockerode
cd $INSTALL_DIR

# Stop existing server
pkill -f "node $INSTALL_DIR/backend/terminal-server.js" || true
sleep 1

nohup node $INSTALL_DIR/backend/terminal-server.js &

# Build console image
cat > $INSTALL_DIR/backend/Dockerfile <<EOF_DOCKERFILE
FROM photon:5.0
RUN sed -i 's/packages.vmware.com/packages-prod.broadcom.com/g' /etc/yum.repos.d/*
RUN tdnf install -y git build-essential tmux ncurses-terminfo
RUN mkdir -p /workspace/photon
WORKDIR /workspace/photon
CMD ["/bin/bash"]
EOF_DOCKERFILE
cd $INSTALL_DIR/backend/
docker build -t photon-builder .

# Download xterm.js and addons
echo "Downloading xterm.js and addons to static/js/xterm..."
mkdir -p $INSTALL_DIR/static/js/xterm
curl -o $INSTALL_DIR/static/js/xterm/xterm.js https://cdn.jsdelivr.net/npm/xterm@4.19.0/lib/xterm.js
curl -o $INSTALL_DIR/static/js/xterm/xterm.css https://cdn.jsdelivr.net/npm/xterm@4.19.0/css/xterm.css
curl -o $INSTALL_DIR/static/js/xterm/xterm-addon-fit.js https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.5.0/lib/xterm-addon-fit.js

# Create console.js external file
mkdir -p $INSTALL_DIR/static/js
cat > $INSTALL_DIR/static/js/console.js <<'EOF_JS'
let term = null;
let socket = null;
let isOpen = false;
let fitAddon = null;
let currentInput = '';

function toggleConsole() {
  const win = document.getElementById('console-window');
  if (isOpen) {
    win.style.display = 'none';
    if (socket) socket.close();
    if (term) term.dispose();
    term = null;
    fitAddon = null;
    isOpen = false;
    // Removed: localStorage.setItem('consoleOpen', 'false');
  } else {
    win.style.display = 'block';
    initConsole();
    isOpen = true;
    // Removed: localStorage.setItem('consoleOpen', 'true');
    if (localStorage.getItem('consoleWelcomeShown') !== 'true') {
      showWelcomeOverlay();
      localStorage.setItem('consoleWelcomeShown', 'true');
    }
  }
}

function initConsole() {
  if (!term) {
    term = new Terminal({ 
      theme: { 
        background: "#1e1e1e", 
        foreground: "#e0e0e0",
        cursor: "#00ff00",
        cursorAccent: "#1e1e1e",
        black: "#000000",
        red: "#ff5555",
        green: "#50fa7b",
        yellow: "#f1fa8c",
        blue: "#bd93f9",
        magenta: "#ff79c6",
        cyan: "#8be9fd",
        white: "#f8f8f2"
      } 
    });
    fitAddon = new FitAddon.FitAddon();
    term.loadAddon(fitAddon);
    term.open(document.getElementById('terminal'));
    fitAddon.fit();
    term.focus();
    term.onData((data) => {
      if (socket && socket.readyState === WebSocket.OPEN) {
        socket.send(data);
      }
      updateCurrentInput(data);
    });
  }
  connectWS();
}

function updateCurrentInput(data) {
  if (data.length === 1 && data.charCodeAt(0) >= 32 && data.charCodeAt(0) <= 126) {
    currentInput += data;
  } else if (data === '\b') {
    if (currentInput.length > 0) currentInput = currentInput.slice(0, -1);
  } else if (data === '\r') {
    currentInput = '';
  } // ignore others like arrows for simplicity
}

function connectWS() {
  if (socket && socket.readyState !== WebSocket.CLOSED) socket.close();
  const sessionID = localStorage.getItem('consoleSessionID');
  const wsUrl = sessionID ? `wss://${location.host}/ws/?session=${sessionID}` : `wss://${location.host}/ws/`;
  socket = new WebSocket(wsUrl);
  socket.onopen = () => {
    currentInput = localStorage.getItem('consoleCurrentInput') || '';
    if (currentInput) {
      socket.send(currentInput);
    }
  };
  socket.onmessage = (event) => {
    try {
      const json = JSON.parse(event.data);
      if (json.type === 'session') {
        localStorage.setItem('consoleSessionID', json.id);
        return;
      }
    } catch (e) {}
    term.write(event.data);
  };
  socket.onclose = () => { term.writeln('Connection closed.'); };
  socket.onerror = () => { term.writeln('Error: Could not connect to server.'); };
}

function resetConsole() {
  if (term) term.reset();
}

function reconnectConsole() {
  connectWS();
}

function showWelcomeOverlay() {
  const overlay = document.createElement('div');
  overlay.id = 'console-welcome';
  overlay.style.position = 'absolute';
  overlay.style.top = '50%';
  overlay.style.left = '50%';
  overlay.style.transform = 'translate(-50%, -50%)';
  overlay.style.background = '#fff';
  overlay.style.padding = '20px';
  overlay.style.borderRadius = '5px';
  overlay.style.boxShadow = '0 0 10px rgba(0,0,0,0.5)';
  overlay.style.zIndex = '1001';
  overlay.innerHTML = `
    <h3>Welcome to Photon OS Console</h3>
    <p>This is an embedded console for Photon OS documentation.</p>
    <p>Start typing commands below.</p>
    <button onclick="this.parentElement.remove()">OK</button>
  `;
  document.getElementById('console-window').appendChild(overlay);
}

// Save currentInput on unload
window.addEventListener('beforeunload', () => {
  localStorage.setItem('consoleCurrentInput', currentInput);
});

// Resize handling
const win = document.getElementById('console-window');
win.addEventListener('resize', () => {
  localStorage.setItem('consoleHeight', win.style.height);
  if (fitAddon) fitAddon.fit();
});

// Resize observer for terminal
new ResizeObserver(() => {
  if (term && isOpen && fitAddon) {
    fitAddon.fit();
  }
}).observe(document.getElementById('terminal'));

// Persist on load (height only, no auto-open)
window.addEventListener('load', () => {
  const win = document.getElementById('console-window');
  win.style.height = localStorage.getItem('consoleHeight') || '300px';
  // Removed auto-toggle: No if (localStorage.getItem('consoleOpen') === 'true') { toggleConsole(); }
});
EOF_JS

# Note: Navbar modifications are now handled in the main installer script to prevent duplicates

# Set up cron job for Docker cleanup
echo "Setting up cron job for Docker container cleanup..."
mkdir -p /etc/cron.d
cat > /etc/cron.d/photon-cleanup <<EOF
*/5 * * * * root docker container prune -f
EOF
chmod 644 /etc/cron.d/photon-cleanup

echo === CONSOLE BACKEND SETUP done. ===
