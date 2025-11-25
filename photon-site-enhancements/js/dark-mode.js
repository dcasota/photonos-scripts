// Dark Mode Toggle Functionality - Simple Icon Toggle

(function() {
  'use strict';

  const STORAGE_KEY = 'theme-preference';
  const THEME_ATTR = 'data-theme';
  
  // Get saved theme or default to light
  function getTheme() {
    return localStorage.getItem(STORAGE_KEY) || 'light';
  }
  
  // Save theme preference
  function saveTheme(theme) {
    localStorage.setItem(STORAGE_KEY, theme);
  }
  
  // Update icon based on theme
  function updateIcon(theme) {
    const icon = document.getElementById('theme-icon');
    if (icon) {
      if (theme === 'dark') {
        // Dark mode active, show sun icon (clicking will go to light)
        icon.className = 'fas fa-sun';
      } else {
        // Light mode active, show moon icon (clicking will go to dark)
        icon.className = 'fas fa-moon';
      }
    }
  }
  
  // Apply theme to document
  function applyTheme(theme) {
    document.documentElement.setAttribute(THEME_ATTR, theme);
    updateIcon(theme);
  }
  
  // Toggle between light and dark
  function toggleTheme(e) {
    if (e) {
      e.preventDefault();
    }
    const currentTheme = getTheme();
    const newTheme = currentTheme === 'light' ? 'dark' : 'light';
    saveTheme(newTheme);
    applyTheme(newTheme);
  }
  
  // Initialize theme on page load
  function init() {
    const savedTheme = getTheme();
    applyTheme(savedTheme);
    
    // Set up toggle listener on the button
    const toggleButton = document.getElementById('theme-toggle');
    if (toggleButton) {
      toggleButton.addEventListener('click', toggleTheme);
    }
  }
  
  // Apply theme immediately to prevent flash (before DOM ready)
  const savedTheme = getTheme();
  applyTheme(savedTheme);
  
  // Run init on DOM ready to attach event listeners
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
  
})();
