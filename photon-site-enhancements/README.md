# Photon OS Documentation Site Enhancements

**Date**: 2025-11-25  
**Commit**: 8b83c7c (from /var/www/photon-site)

## Overview

This directory contains all the enhancements added to the Photon OS documentation site, including interactive console, dark mode toggle, and code block copy/run buttons.

## Features Included

### 1. Interactive Console Integration
- **WebSocket-based terminal**: Real-time command execution in a Docker container
- **Console button in navbar**: Terminal icon for easy access
- **Session management**: 5-minute timeout with automatic cleanup
- **Files**: 
  - `layouts/partials/hooks/body-end.html` (console window HTML)
  - `js/console.js` (WebSocket client)

### 2. Dark/Light Mode Toggle
- **Simple icon toggle**: Moon/sun icon in navbar
- **Persistent preference**: Saved in localStorage
- **Smooth transitions**: CSS-based theme switching
- **Files**:
  - `js/dark-mode.js` (toggle logic - 862 bytes)
  - `css/dark-mode.css` (theme CSS variables - 3.1KB)
  - `config.toml` (darkmode = true)

### 3. Enhanced Code Blocks
- **Run button** (blue, #007bff): Sends command to console
- **Copy button** (green, #28a745): Copies to clipboard
- **Visual feedback**: Success (✓ Copied!) / Error (✗ Failed)
- **Smart filtering**: Auto-enhances appropriate code blocks only
- **Files**:
  - `layouts/shortcodes/command-box.html` (shortcode with buttons)
  - `layouts/partials/hooks/body-end.html` (auto-enhancement script)

### 4. Hugo Compatibility Fixes
- Fixed `.Site.IsServer` → `hugo.IsServer` for Hugo 0.152.2
- Google Analytics template compatibility
- Template error handling

## Directory Structure

```
photon-site-enhancements/
├── README.md                           (this file)
├── config.toml                         (Hugo config with darkmode enabled)
├── layouts/
│   ├── _default/
│   │   ├── _markup/render-link.html   (link rendering)
│   │   └── index.json                 (search index)
│   ├── partials/
│   │   └── hooks/body-end.html        (console + code enhancement)
│   ├── shortcodes/
│   │   └── command-box.html           (Run + Copy buttons)
│   └── sitemap.xml                    (sitemap template)
├── css/
│   ├── dark-mode.css                  (dark theme styles)
│   └── search-overlay.css             (search styling)
└── js/
    ├── console.js                     (WebSocket terminal)
    ├── dark-mode.js                   (theme toggle)
    ├── search.js                      (search functionality)
    ├── lunr.min.js                    (search library)
    └── xterm/                         (terminal emulator)
```

## Installation

### On a Photon OS Hugo Site

1. **Copy files to Hugo site**:
```bash
cp -r layouts/* /var/www/photon-site/layouts/
cp -r css/* /var/www/photon-site/static/css/
cp -r js/* /var/www/photon-site/static/js/
cp config.toml /var/www/photon-site/  # Merge with existing config
```

2. **Install backend** (for console feature):
```bash
cd /var/www/photon-site/backend
npm install ws dockerode
node terminal-server.js &
```

3. **Rebuild Hugo site**:
```bash
cd /var/www/photon-site
hugo --cleanDestinationDir --minify
chown -R nginx:nginx public
```

4. **Test features**:
- Visit site
- Click console button (terminal icon)
- Click dark mode toggle (moon/sun icon)
- Test code block copy/run buttons

## Features

### Console Button Usage
1. Click terminal icon in navbar
2. Console window appears at bottom
3. Click "Run" on any code block
4. Command executes in console
5. See real-time output

### Dark Mode Toggle Usage
1. Click moon icon in navbar
2. Theme switches to dark mode
3. Icon changes to sun
4. Preference saved in localStorage
5. Persists across page loads

### Code Block Buttons Usage
1. Hover over any code block
2. See Run (blue) and Copy (green) buttons
3. Click Copy: text copied to clipboard
4. Click Run: command sent to console
5. Visual feedback on success/error

## Technical Details

### Browser Requirements
- WebSocket support (for console)
- localStorage (for dark mode preference)
- Clipboard API (for copy button)
- CSS variables (for theming)

### Hugo Version
- **Minimum**: Hugo 0.111.3
- **Tested on**: Hugo 0.152.2+extended
- **Compatibility**: Fixed `.Site.IsServer` deprecation

### Backend Requirements (Optional)
Console feature requires Node.js backend:
- Node.js 14+
- `ws` package (WebSocket)
- `dockerode` package (Docker API)
- Docker daemon running

## Configuration

### Enable Dark Mode
In `config.toml`:
```toml
[params]
  darkmode = true
```

### Console Backend Port
Default: `3001`
Change in `js/console.js`:
```javascript
const wsUrl = 'ws://127.0.0.1:3001';
```

### Button Colors
In `layouts/partials/hooks/body-end.html`:
```javascript
runBtn.style.backgroundColor = '#007bff';  // Blue
copyBtn.style.backgroundColor = '#28a745'; // Green
```

## Testing

### Verify Installation
```bash
# Check files exist
ls layouts/partials/hooks/body-end.html
ls layouts/shortcodes/command-box.html
ls static/js/dark-mode.js
ls static/css/dark-mode.css

# Test Hugo build
hugo --minify

# Check for errors
grep -r "\.Site\.IsServer" themes/
```

### Manual Testing
1. ✓ Console button appears in navbar
2. ✓ Dark mode toggle appears after console button
3. ✓ Code blocks show Run and Copy buttons
4. ✓ Dark mode persists after refresh
5. ✓ Console connects and executes commands
6. ✓ Copy button uses clipboard API

## Troubleshooting

### Console Not Working
- Check backend is running: `ps aux | grep terminal-server`
- Check WebSocket port: `netstat -an | grep 3001`
- Check browser console for errors
- Verify Docker is running

### Dark Mode Not Saving
- Check localStorage in browser DevTools
- Verify `dark-mode.js` is loaded
- Check for JavaScript errors

### Code Blocks Missing Buttons
- Verify `body-end.html` is loaded
- Check code blocks have `<pre><code>` structure
- Smart filter may exclude (>5 lines, shebang, etc.)

## Known Issues

1. **Footer Dates**: This version shows local commit dates instead of upstream history
2. **Backend Dependency**: Console requires separate Node.js backend
3. **Hugo Version**: Template syntax requires Hugo 0.111.3+

## Version History

- **2025-11-25**: Initial version (commit 8b83c7c)
  - Interactive console integration
  - Dark/light mode toggle
  - Code block copy/run buttons
  - Hugo 0.152.2 compatibility

## License

Same as Photon OS documentation (Apache 2.0 or respective upstream license)

## Related

- Main PR: https://github.com/dcasota/photon/pull/2
- Documentation: /root/PUSH_AND_PR_COMPLETE_GUIDE.md
- Success report: /root/PR_CREATED_SUCCESS.md

## Support

For questions or issues with these enhancements, refer to:
- Installation guide above
- Troubleshooting section
- Main documentation at /root/photonos-scripts/docsystem/
