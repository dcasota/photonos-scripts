let term = null;
let socket = null;
let isOpen = false;
let fitAddon = null;
let currentInput = '';

// Function to send command to console
function sendCommand(command) {
  const wasOpen = isOpen;
  if (!isOpen) {
    toggleConsole();
  }
  
  // Wait for WebSocket to be ready, checking periodically
  const sendWhenReady = (attempts = 0) => {
    if (socket && socket.readyState === WebSocket.OPEN) {
      // Send the command
      socket.send(command + '\r');
      currentInput = '';
      // Write to terminal for visual feedback
      if (term) {
        term.write('\r\n$ ' + command + '\r\n');
      }
    } else if (attempts < 50) { // Try for up to 5 seconds
      setTimeout(() => sendWhenReady(attempts + 1), 100);
    } else {
      console.error('Failed to connect to WebSocket after 5 seconds');
      if (term) {
        term.write('\r\nError: Could not connect to terminal server\r\n');
      }
    }
  };
  
  // Start checking after a delay (longer if console was just opened)
  setTimeout(() => sendWhenReady(), wasOpen ? 100 : 1000);
}

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
    term = new Terminal({ theme: { background: "#1e1e1e" } });
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
