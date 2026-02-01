/*
 * hab_iso.h
 *
 * ISO manipulation functions for HABv4
 *
 * Copyright 2024 HABv4 Project
 * SPDX-License-Identifier: GPL-3.0+
 */

#ifndef HAB_ISO_H
#define HAB_ISO_H

/* Function to verify ISO content */
int verify_iso_content(const char *iso_mount_dir);

/* Function to repack the ISO */
int repack_iso(const char *iso_extract_dir, const char *output_iso_path, const char *volume_id);

#endif /* HAB_ISO_H */
