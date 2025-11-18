#!/bin/bash

if [ -z "$INSTALL_DIR" ]; then
  echo "Error: Variable INSTALL_DIR is not set. This sub-script must be called by installer.sh"
  exit 1
fi

echo === SEARCH OVERLAY SETUP ===

# Create search index template for Hugo
mkdir -p $INSTALL_DIR/layouts/_default
cat > $INSTALL_DIR/layouts/_default/index.json <<'EOF_SEARCH_INDEX'
{{- $index := slice -}}
{{- range where .Site.RegularPages "Type" "ne" "json" -}}
  {{- $item := dict "title" .Title "tags" (.Params.tags | default slice) "contents" (.Plain | plainify) "permalink" .Permalink "summary" (.Summary | plainify) -}}
  {{- $index = $index | append $item -}}
{{- end -}}
{{- $index | jsonify -}}
EOF_SEARCH_INDEX

mkdir -p $INSTALL_DIR/static/js
wget -O $INSTALL_DIR/static/js/lunr.min.js https://unpkg.com/lunr@2.3.9/lunr.min.js || echo "Warning: Failed to download Lunr.js."

mkdir -p $INSTALL_DIR/static/css
cat > $INSTALL_DIR/static/css/search-overlay.css <<'EOF_SEARCH_CSS'
/* Search Button removed - using original Docsy search input */

/* Overlay */
.search-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  background: rgba(0, 0, 0, 0.5);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  z-index: 9999;
  opacity: 0;
  visibility: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: opacity 0.3s ease, visibility 0.3s ease;
}

.search-overlay.active {
  opacity: 1;
  visibility: visible;
}

/* Search Panel */
.search-panel {
  background: rgba(255, 255, 255, 0.1);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 12px;
  padding: 2rem;
  max-width: 600px;
  width: 90%;
  max-height: 80vh;
  overflow-y: auto;
  position: relative;
  box-shadow: 0 20px 40px rgba(0,0,0,0.1);
}

.search-close {
  position: absolute;
  top: 1rem;
  right: 1rem;
  background: none;
  border: none;
  color: inherit;
  cursor: pointer;
  padding: 0.5rem;
  border-radius: 50%;
  transition: background-color 0.2s;
}

#search-input {
  width: 100%;
  padding: 1rem;
  border: none;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.2);
  color: inherit;
  font-size: 1.2rem;
  outline: none;
  backdrop-filter: blur(10px);
}

#search-input::placeholder {
  color: rgba(255, 255, 255, 0.7);
}

.search-results {
  margin-top: 1rem;
  color: inherit;
}

.search-results ul {
  list-style: none;
  padding: 0;
}

.search-results li {
  margin-bottom: 1rem;
}

.search-results a {
  color: inherit;
  text-decoration: none;
}

.search-results a:hover {
  text-decoration: underline;
}
EOF_SEARCH_CSS

cat > $INSTALL_DIR/static/js/search.js <<'EOF_SEARCH_JS'
let searchIndex = null;
let documents = {};

document.addEventListener('DOMContentLoaded', function() {
  const overlay = document.getElementById('search-overlay');
  const close = document.getElementById('search-close');
  const input = document.getElementById('search-input');
  const results = document.getElementById('search-results');

  // Load search index
  async function loadIndex() {
    try {
      const response = await fetch('/index.json');
      const pages = await response.json();
      documents = {};
      pages.forEach(doc => documents[doc.permalink] = doc);

      if (typeof lunr !== 'undefined') {
        searchIndex = lunr(function () {
          this.ref('permalink');
          this.field('title', { boost: 10 });
          this.field('tags', { boost: 5 });
          this.field('contents');
          this.field('summary', { boost: 2 });
          pages.forEach(page => this.add(page));
        });
      }
    } catch (e) {
      console.error('Search index load failed', e);
    }
  }

  loadIndex();

  // Open / close
  function openSearch() {
    overlay.classList.add('active');
    document.body.classList.add('search-open');
    input.focus();
  }

  function closeSearch() {
    overlay.classList.remove('active');
    document.body.classList.remove('search-open');
    input.value = '';
    results.innerHTML = '';
    if (originalSearchInput) originalSearchInput.value = '';
  }

  if (close) close.addEventListener('click', closeSearch);
  overlay.addEventListener('click', function(e) {
    if (e.target === overlay) closeSearch();
  });

  // Search functionality
  input.addEventListener('input', function(e) {
    const query = e.target.value.trim();
    if (originalSearchInput) originalSearchInput.value = query;
    if (query.length < 2) {
      results.innerHTML = '';
      return;
    }
    if (!searchIndex) {
      results.innerHTML = '<p>Loading search...</p>';
      return;
    }
    const searchResults = searchIndex.search(query);
    let html = '<ul>';
    searchResults.forEach(r => {
      const doc = documents[r.ref];
      if (doc) {
        html += `<li><a href="${doc.permalink}">${doc.title}</a><br><small>${doc.summary || ''}</small></li>`;
      }
    });
    html += '</ul>';
    if (searchResults.length === 0) {
      html = '<p>No results found.</p>';
    }
    results.innerHTML = html;
  });

  // Close on Escape key
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && overlay.classList.contains('active')) {
      closeSearch();
    }
  });

  // === Hook to original Docsy sidebar search input ===
  const originalSearchInput = document.querySelector('input[placeholder*="Search this site"]');
  if (originalSearchInput) {
    // Hide any original results dropdowns
    ['.td-search-results', '.search-results', '#search-results', '#results'].forEach(sel => {
      const res = document.querySelector(sel);
      if (res) res.style.display = 'none';
    });

    // Open overlay on focus
    originalSearchInput.addEventListener('focus', function() {
      openSearch();
      input.value = this.value || '';
      input.dispatchEvent(new Event('input'));
    });

    // Sync typing from original to overlay
    originalSearchInput.addEventListener('input', function(e) {
      input.value = e.target.value;
      input.dispatchEvent(new Event('input'));
    });
  }

  // Sync typing from overlay to original
  if (input && originalSearchInput) {
    input.addEventListener('input', function(e) {
      originalSearchInput.value = e.target.value;
    });
  }
});
EOF_SEARCH_JS

# Add console and search window HTML/JS to body-end partial
mkdir -p $INSTALL_DIR/layouts/partials/hooks
cat > $INSTALL_DIR/layouts/partials/hooks/body-end.html <<'EOF_BODY_END'
<div id="console-window" style="display: none; position: fixed; bottom: 0; left: 0; right: 0; height: 300px; background: #fff; border-top: 1px solid #000; z-index: 1000; resize: vertical; overflow: hidden; box-shadow: 0 -2px 10px rgba(0,0,0,0.2);">
  <div id="console-header" style="background: #ddd; padding: 5px; display: flex; justify-content: space-between; align-items: center;">
    <span>Photon OS Console</span>
    <div>
      <button onclick="resetConsole()">Reset</button>
      <button onclick="reconnectConsole()">Reconnect</button>
      <button onclick="toggleConsole()">Close</button>
    </div>
  </div>
  <div id="terminal" style="width: 100%; height: calc(100% - 30px); background: #1e1e1e;"></div>
</div>

<!-- Search Overlay HTML -->
<div id="search-overlay" class="search-overlay" role="dialog" aria-modal="true" aria-labelledby="search-input">
  <div class="search-panel">
    <button id="search-close" class="search-close" aria-label="Close search">
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor">
        <line x1="18" y1="6" x2="6" y2="18"></line>
        <line x1="6" y1="6" x2="18" y2="18"></line>
      </svg>
    </button>
    <input type="search" id="search-input" placeholder="Search..." autofocus>
    <div id="search-results" class="search-results">
      <!-- Results will be populated by JS -->
    </div>
  </div>
</div>

<link rel="stylesheet" href="/css/search-overlay.css">
<script src="/js/lunr.min.js"></script>
<link rel="stylesheet" href="/js/xterm/xterm.css">
<script src="/js/xterm/xterm.js"></script>
<script src="/js/xterm/xterm-addon-fit.js"></script>
<script src="/js/console.js"></script>
<script src="/js/search.js"></script>
EOF_BODY_END

echo "Add search outputs to config.toml for Lunr index generation ..."
if ! grep -q "\[outputs\]" $INSTALL_DIR/config.toml; then
  cat >> $INSTALL_DIR/config.toml <<EOF_OUTPUTS

[outputs]
home = ["HTML", "RSS", "JSON"]
EOF_OUTPUTS
else
  sed -i '/\[outputs\]/,/^$/s/home = \["HTML", "RSS"\]/home = ["HTML", "RSS", "JSON"]/' $INSTALL_DIR/config.toml
fi

echo === SEARCH OVERLAY SETUP done. ===
