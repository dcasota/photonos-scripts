#!/usr/bin/env python3
"""
photon-os-installer progress_bar AttributeError Fix

This file contains the minimal code changes needed to fix the bug where
the installer crashes with "AttributeError: 'Installer' object has no
attribute 'progress_bar'" when using kickstart with ui:true.

Bug report: https://github.com/vmware/photon-os-installer/issues/XXX

ROOT CAUSE:
-----------
1. When ui:true in kickstart, install_config['ui'] is True
2. execute() method calls curses.wrapper(self._install)
3. Inside _install(), self.progress_bar is created ONLY after curses init succeeds (line ~763)
4. If any exception occurs before progress_bar is created, exit_gracefully() is called
5. exit_gracefully() checks 'if self.install_config['ui']:' and calls self.progress_bar.hide()
6. This fails with AttributeError because progress_bar was never created as an instance attribute

AFFECTED CODE LOCATIONS:
------------------------
- __init__(): Missing initialization of self.progress_bar
- exit_gracefully(): Assumes progress_bar exists when ui:true
- _ansible_run(): Assumes progress_bar exists when ui:true
- _docker_images(): Assumes progress_bar exists when ui:true
- _initialize_system(): Assumes progress_bar exists when ui:true
- _finalize_system(): Assumes progress_bar exists when ui:true
- _cleanup_cache(): Assumes progress_bar exists when ui:true
- _cleanup_install_repo(): Assumes progress_bar exists when ui:true
- _setup_grub(): Assumes progress_bar exists when ui:true
- _partition_disks(): Assumes progress_bar exists when ui:true
- _install_packages(): Assumes progress_bar exists when ui:true (multiple locations)

FIX:
----
Option A (Minimal - Recommended): Initialize progress_bar to None in __init__()
and add null checks before usage.

Option B (Alternative): Use hasattr() checks before accessing progress_bar.

Option C (Defensive): Create a helper method for safe progress_bar access.
"""

# =============================================================================
# OPTION A: Minimal Fix - Initialize to None + null checks
# =============================================================================

# Change 1: In __init__() method, add after line ~127 (after self.cwd = os.getcwd()):
"""
        self.progress_bar = None  # Initialize to None to prevent AttributeError
        self.window = None        # Initialize window to None for consistency
"""

# Change 2: In exit_gracefully() method, change:
# FROM:
"""
        if not self.exiting and self.install_config:
            self.exiting = True
            if self.install_config['ui']:
                self.progress_bar.hide()
                self.window.addstr(0, 0, 'Oops, Installer got interrupted.\\n\\n' +
                                   'Press any key to get to the bash...')
                self.window.content_window().getch()
"""
# TO:
"""
        if not self.exiting and self.install_config:
            self.exiting = True
            if self.install_config['ui'] and self.progress_bar is not None:
                self.progress_bar.hide()
            if self.install_config['ui'] and self.window is not None:
                self.window.addstr(0, 0, 'Oops, Installer got interrupted.\\n\\n' +
                                   'Press any key to get to the bash...')
                self.window.content_window().getch()
"""

# Change 3: In ALL other methods that use progress_bar, change pattern:
# FROM:
"""
        if self.install_config['ui']:
            self.progress_bar.update_message('...')
"""
# TO:
"""
        if self.install_config['ui'] and self.progress_bar is not None:
            self.progress_bar.update_message('...')
"""


# =============================================================================
# OPTION B: Alternative - Use hasattr() checks
# =============================================================================

# No change to __init__() needed

# Change in exit_gracefully() and all other methods:
# FROM:
"""
        if self.install_config['ui']:
            self.progress_bar.hide()
"""
# TO:
"""
        if self.install_config['ui'] and hasattr(self, 'progress_bar'):
            self.progress_bar.hide()
"""


# =============================================================================
# OPTION C: Defensive - Helper method (most robust)
# =============================================================================

# Add new helper method after __init__():
"""
    def _update_progress(self, message=None, increment=None, num_items=None, loading=None):
        '''
        Safely update progress bar if UI mode is enabled and progress_bar exists.
        '''
        if not self.install_config.get('ui', False):
            return
        if not hasattr(self, 'progress_bar') or self.progress_bar is None:
            return
        
        if message is not None:
            self.progress_bar.update_message(message)
        if increment is not None:
            self.progress_bar.increment(increment)
        if num_items is not None:
            self.progress_bar.update_num_items(num_items)
        if loading is not None:
            self.progress_bar.show_loading(loading)
    
    def _hide_progress(self):
        '''
        Safely hide progress bar if it exists.
        '''
        if hasattr(self, 'progress_bar') and self.progress_bar is not None:
            self.progress_bar.hide()
"""

# Then replace all direct progress_bar calls with helper method calls:
# FROM:
"""
        if self.install_config['ui']:
            self.progress_bar.update_message('Partitioning...')
"""
# TO:
"""
        self._update_progress(message='Partitioning...')
"""


# =============================================================================
# COMPLETE FIXED exit_gracefully() METHOD (Option A)
# =============================================================================

def exit_gracefully_fixed(self, signal1=None, frame1=None):
    """
    This will be called if the installer interrupted by Ctrl+C, exception
    or other failures
    """
    del signal1
    del frame1
    if not self.exiting and self.install_config:
        self.exiting = True
        # FIX: Check if progress_bar exists before using it
        if self.install_config['ui'] and self.progress_bar is not None:
            self.progress_bar.hide()
        # FIX: Check if window exists before using it
        if self.install_config['ui'] and self.window is not None:
            self.window.addstr(0, 0, 'Oops, Installer got interrupted.\n\n' +
                               'Press any key to get to the bash...')
            self.window.content_window().getch()

        self._cleanup_install_repo()
        self._unmount_all()
        self._detach_loop_devices()
        self._detach_lvs()


# =============================================================================
# COMPLETE FIXED __init__() ADDITIONS
# =============================================================================

# Add these lines in __init__() after "self.cwd = os.getcwd()":
"""
        # FIX: Initialize UI components to None to prevent AttributeError
        # These are created in _install() only when curses initializes successfully
        self.progress_bar = None
        self.window = None
"""


# =============================================================================
# SUMMARY OF ALL LOCATIONS REQUIRING CHANGES
# =============================================================================

LOCATIONS_TO_FIX = [
    # (method_name, line_number_approx, change_description)
    ("__init__", 127, "Add: self.progress_bar = None; self.window = None"),
    ("exit_gracefully", 836, "Change: if ui -> if ui and progress_bar is not None"),
    ("exit_gracefully", 837, "Change: if ui -> if ui and window is not None (for window access)"),
    ("_ansible_run", 866, "Change: if ui -> if ui and progress_bar is not None"),
    ("_docker_images", 927, "Change: if ui -> if ui and progress_bar is not None"),
    ("_initialize_system", 1284, "Change: if ui -> if ui and progress_bar is not None"),
    ("_finalize_system", 1389, "Change: if ui -> if ui and progress_bar is not None"),
    ("_cleanup_cache", 1405, "Change: if ui -> if ui and progress_bar is not None"),
    ("_cleanup_install_repo", 1425, "Change: if ui -> if ui and progress_bar is not None"),
    ("_setup_grub", 1440, "Change: if ui -> if ui and progress_bar is not None"),
    ("_install_packages", 1644, "Change: if ui -> if ui and progress_bar is not None"),
    ("_install_packages", 1654, "Change: if ui -> if ui and progress_bar is not None"),
    ("_install_packages", 1657, "Change: if ui -> if ui and progress_bar is not None"),
    ("_install_packages", 1665, "Change: if ui -> if ui and progress_bar is not None"),
    ("_install_packages", 1667, "Change: if ui -> if ui and progress_bar is not None"),
    ("_partition_disks", 2129, "Change: if ui -> if ui and progress_bar is not None"),
]

if __name__ == "__main__":
    print("photon-os-installer progress_bar AttributeError Fix")
    print("=" * 60)
    print()
    print("This fix addresses the bug where the installer crashes with:")
    print("  AttributeError: 'Installer' object has no attribute 'progress_bar'")
    print()
    print("Locations requiring changes:")
    print("-" * 60)
    for method, line, desc in LOCATIONS_TO_FIX:
        print(f"  {method}() ~line {line}: {desc}")
    print()
    print("Recommended fix: Option A (initialize to None + null checks)")
    print("See patch file: photon-os-installer-progress_bar-fix.patch")
