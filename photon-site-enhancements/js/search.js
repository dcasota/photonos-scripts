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
