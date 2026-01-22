/*
 * HabPreLoader.c - HAB Secure Boot PreLoader
 *
 * Based on efitools PreLoader by James Bottomley
 * Modified for HABv4 Secure Boot project
 *
 * This PreLoader:
 * 1. Installs security policy override using efitools library
 * 2. Loads grubx64_real.efi (VMware's signed GRUB)
 *
 * Copyright 2012 James Bottomley <James.Bottomley@HansenPartnership.com>
 * Copyright 2024 HABv4 Project
 *
 * SPDX-License-Identifier: GPL-3.0+
 */

#include <efi.h>
#include <efilib.h>

#include <console.h>
#include <errors.h>
#include <guid.h>
#include <security_policy.h>
#include <execute.h>

#include "hashlist.h"

/* Target loader - VMware's signed GRUB */
CHAR16 *loader = L"grubx64_real.efi";

/* HashTool for manual hash enrollment if needed */
CHAR16 *hashtool = L"HashTool.efi";

EFI_STATUS
efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *systab)
{
	EFI_STATUS status;
	UINT8 SecureBoot;
	UINTN DataSize = sizeof(SecureBoot);

	InitializeLib(image, systab);

	console_reset();

	/* Check if Secure Boot is enabled */
	status = RT->GetVariable(L"SecureBoot",
				 &GV_GUID, NULL, &DataSize, &SecureBoot);
	if (status != EFI_SUCCESS) {
		Print(L"HAB: Not a Secure Boot Platform (%r)\n", status);
		goto override;
	}

	if (!SecureBoot) {
		Print(L"HAB: Secure Boot Disabled\n");
		goto override;
	}

	Print(L"HAB: Secure Boot Active - Installing security policy\n");

	/*
	 * Install the security policy with MOK-based verification.
	 * This is the key to making Secure Boot work:
	 * - security_policy_mok_override: Check MokSBState for insecure mode
	 * - security_policy_mok_allow: Check if hash is in MokList
	 * - security_policy_mok_deny: Check if hash is in dbx/MokListX
	 */
	status = security_policy_install(security_policy_mok_override,
					 security_policy_mok_allow,
					 security_policy_mok_deny);
	if (status != EFI_SUCCESS) {
		console_error(L"HAB: Failed to install security policy",
			      status);
		goto override;
	}

	Print(L"HAB: Security policy installed\n");

	/* Install any statically compiled hashes (empty for HAB) */
	security_protocol_set_hashes(_tmp_tmp_hash, _tmp_tmp_hash_len);

	/* Check for 'H' key to start HashTool */
	if (console_check_for_keystroke('H'))
		goto start_hashtool;

	/* Execute the main loader */
	Print(L"HAB: Loading %s\n", loader);
	status = execute(image, loader);

	if (status == EFI_SUCCESS)
		goto out;

	/* Handle security violations */
	if (status != EFI_SECURITY_VIOLATION && status != EFI_ACCESS_DENIED) {
		CHAR16 buf[256];

		StrCpy(buf, L"HAB: Failed to start ");
		StrCat(buf, loader);
		console_error(buf, status);

		goto out;
	}

	/* Security violation - offer to start HashTool */
	console_alertbox((CHAR16 *[]) {
			L"HAB: Failed to start loader",
			L"",
			L"The loader grubx64_real.efi was not trusted.",
			L"Please enroll its hash via MokManager and try again.",
			L"",
			L"Press any key to continue...",
			NULL
		});

	for (;;) {
	start_hashtool:
		status = execute(image, hashtool);

		if (status != EFI_SUCCESS) {
			CHAR16 buf[256];

			StrCpy(buf, L"HAB: HashTool not found: ");
			StrCat(buf, hashtool);
			console_error(buf, status);

			goto out;
		}

		/* Retry loader after HashTool */
		status = execute(image, loader);
		if (status == EFI_ACCESS_DENIED
		    || status == EFI_SECURITY_VIOLATION) {
			int selection = console_select((CHAR16 *[]) {
				L"Loader still giving security error",
				NULL
			}, (CHAR16 *[]) {
				L"Start HashTool",
				L"Exit",
				NULL
			}, 0);
			if (selection == 0)
				continue;
		}

		break;
	}

 out:
	status = security_policy_uninstall();
	if (status != EFI_SUCCESS)
		console_error(L"HAB: Failed to uninstall security policy", status);

	return status;

 override:
	/* Direct execute without security policy (Secure Boot disabled) */
	Print(L"HAB: Loading %s (no security policy)\n", loader);
	status = execute(image, loader);
	
	if (status != EFI_SUCCESS) {
		CHAR16 buf[256];

		StrCpy(buf, L"HAB: Failed to start ");
		StrCat(buf, loader);
		console_error(buf, status);
	}

	return status;
}
