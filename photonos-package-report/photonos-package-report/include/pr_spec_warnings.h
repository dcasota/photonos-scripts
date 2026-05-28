/* pr_spec_warnings.h — per-spec warning lookup.
 *
 * Phase M task M13. Mirrors PS L 4442-4519: a static set of
 * (spec_basename, warning_text) tuples in 6 categories that PS emits
 * via `if ($currentTask.Spec -ilike '<spec>') { $warning = ... }` chains.
 * Some entries are gated on `$UpdateAvailable -eq ""`.
 *
 * The function returns a static-storage string (no free required) or
 * NULL when the spec doesn't match any rule. PS semantics: when a spec
 * matches multiple rules across the 6 chains, the LAST match wins —
 * so callers may invoke this function once and use its return as the
 * final warning value.
 *
 * Multiple matches in practice are absent — each PS chain has unique
 * spec basenames and the chains don't overlap. We preserve the
 * semantic anyway for defensive parity.
 */
#ifndef PR_SPEC_WARNINGS_H
#define PR_SPEC_WARNINGS_H

/* Returns a pointer to a static-storage warning string, or NULL.
 *
 *   spec               — basename like "abupdate.spec" (case-insensitive)
 *   update_available   — current value of UpdateAvailable column. Some
 *                        rules only emit when this is empty.
 */
const char *pr_spec_warning(const char *spec, const char *update_available);

/* M105: returns 1 if `spec`'s entry in the warning table is a
 * VMware-internal Source0 entry (PS L 4490-4508). Used by
 * check_urlhealth.c to skip the update-detection block for these specs
 * (mirroring PS, which emits the "Info" warning and leaves col5/6 empty). */
int pr_spec_is_vmware_internal(const char *spec);

#endif /* PR_SPEC_WARNINGS_H */
