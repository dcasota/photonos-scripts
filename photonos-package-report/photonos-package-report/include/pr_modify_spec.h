/* pr_modify_spec.h — port of photonos-package-report.ps1 L 1394-1480
 * (function ModifySpecFile).
 *
 * Given a successfully-detected update (HealthUpdateURL=200), rewrite
 * the spec file with the new version + release + SHA line + changelog
 * entry, and write the result to
 *   <UpstreamsDir>/<photonDir>/SPECS_NEW[_C]/<Name>/<basename>-<Update>.spec
 *
 * Per-spec switches mirror the PS call site (L5220-5222):
 *   - openjdk8.spec   → Version = 1.8.0.<Update>
 *   - netcat.spec     → also update %global commit_id
 *   - default         → plain Version = <Update>
 *
 * Lifecycle:
 *   - Env-gated by PR_MODIFY_SPEC: when unset, this is a no-op (preserves
 *     C-side parity-gate behaviour — only the .prn diff matters today).
 *   - When set, output dir defaults to "SPECS_NEW_C" to keep PS's
 *     SPECS_NEW writes byte-stable for the 90-day-green journal. After
 *     byte-identical validation against PS, the dir name flips.
 *
 * Returns 0 on success (file written), -1 on a recoverable skip
 * (e.g. spec file missing), or -2 on a hard error (write failed).
 */
#ifndef PR_MODIFY_SPEC_H
#define PR_MODIFY_SPEC_H

#include "pr_types.h"

int pr_modify_spec_file(const pr_task_t *task,
                        const char      *working_dir,
                        const char      *upstreams_dir,
                        const char      *photon_dir,
                        const char      *update_avail,
                        const char      *sha_line,
                        int              openjdk8,
                        const char      *commit_id,
                        const char      *out_subdir);

#endif /* PR_MODIFY_SPEC_H */
