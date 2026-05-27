# FRD-018-listing-scraper: HTTP directory-listing scraper

**Feature ID**: FRD-018-listing-scraper
**Related PRD Requirements**: REQ-7 (urlhealth), REQ-12 (clone/fetch)
**Related ADRs**: ADR-0001, ADR-0002 (libcurl), ADR-0006
**PS source range**: photonos-package-report.ps1 L 4258-4283
**Status**: Accepted
**Last updated**: 2026-05-18

---

## 1. Overview

PS detects "latest" version for specs **without a `gitSource`** by
GET-ing the **directory listing page** of the spec's Source0 URL
(via `split-path $Source0 -Parent`), then extracting all `<a href="...">`
values from the HTML and treating them as candidate version names.

For example, for GConf.spec with Source0:

    http://ftp.gnome.org/pub/gnome/sources/GConf/3.2/GConf-3.2.5.tar.xz

PS GETs `http://ftp.gnome.org/pub/gnome/sources/GConf/3.2/`, finds
`<a href="GConf-3.2.6.tar.xz">`, etc. After the name-strip pipeline
(M19 augmentations + Clean-VersionNames + the no-letter filter) the
candidate list reduces to `{2.0.5, ..., 3.2.6}` and `pr_get_latest_name`
returns `3.2.6`.

The C port lacked this entire path — for non-git specs, C never set
`UpdateAvailable` at all, leaving 504 specs in the dominant 4.0 diff
bucket.

This FRD specifies the listing-scraper port.

## 2. Functional requirements

### 2.1 New API: `pr_scrape_listing()`

```c
/* GET the URL (libcurl, max body 1 MiB), parse the response body as
 * HTML, extract every <a href="..."> value. Returns names[] / n.
 * Caller frees with pr_git_tags_free.
 *
 * Returns 0 on success (even when 0 hrefs found); -1 on HTTP error
 * or body too large. */
int pr_scrape_listing(const char *url, char ***out_names, size_t *out_n);
```

### 2.2 Wiring in CheckURLHealth

When `row->gitSource` is empty (no git clone path) AND `allow_network`
is on:

1. Compute `listing_url = dirname(Source0)`. PS L 4000:
   `$SourceTagURL = (split-path $Source0 -Parent).Replace('\','/').`
2. HEAD-probe `listing_url`; if non-200, skip (matches PS L 4212 guard).
3. `pr_scrape_listing(listing_url)` → `names[]`.
4. Apply the same post-processing pipeline currently used for git
   tags: `apply_replace_strings` (row.replaceStrings),
   `apply_name_replace_augmentations` (M19).
5. `pr_get_latest_name(names)` → `latest`.
6. From here, the rest of the existing rc==1/0/-1 branch logic
   applies — UpdateAvailable / UpdateURL / Health / SHA / DownloadName.

### 2.3 HTML parsing scope

Minimal: regex-extract `<a\s+href\s*=\s*"([^"]+)"|<a\s+href\s*=\s*'([^']+)'`
matches. PS uses `Invoke-WebRequest` which gives `.Links.href` via the
.NET HTML parser. For the directory-listing pages we care about
(ftp.gnome.org, archive.apache.org, downloads.sourceforge.net,
launchpad.net release pages, etc.), simple href extraction is
sufficient — those pages don't use JS-rendered content or nested
quoting tricks.

PCRE2 is already a build dep (used by `parse_directory`); reuse.

## 3. Bit-identical assertions

- The href list from `pr_scrape_listing` must match what
  `Invoke-WebRequest -UseBasicParsing | .Links.href` would yield for
  the same URL.
- Post-scrape pipeline (strip / filter / select-latest) reuses the
  existing C functions. No new normalisation logic in this FRD.

## 4. Acceptance tests

- Unit: feed a fixture HTML response into `pr_scrape_listing`; assert
  the extracted href list matches expected.
- Integration: against a representative spec from each upstream
  family (gnome.org for GConf, sourceforge for atftp, apache for
  apr-util, launchpad for apparmor), confirm C `.prn` row col 5
  (UpdateAvailable) becomes non-empty and equals PS's value.
- Parity-diff against PS snapshot for the in-scope specs: byte-zero
  on cols 5/6/9/10/11 for non-git specs that now use the scraper.

## 5. Dependencies

- ADR-0001 (C language), ADR-0002 (libcurl)
- PCRE2 (existing build dep)
- FRD-006 (urlhealth HEAD probe — reused for the guard at step 2)
- FRD-011 (CheckURLHealth orchestrator — wiring point)

## 6. Open questions

- **GitHub release-page fallback?** PS sometimes falls back to
  `<repo>/releases/atom` when listing isn't available. Out of scope
  for this FRD; tracked as FRD-019.
- **Body-size cap.** 1 MiB should cover any reasonable listing page.
  If a real-world page exceeds, document the limit; don't grow.
- **Header set.** PS sends Chrome-style headers (L 4263-4283) to dodge
  bot detection on some hosts. Mirror these initially; reduce only if
  shown to cause issues.
- **Two-stage fetch (M99).** PS L 4378-4404 actually does the listing
  GET in *two* stages: a primary bare `Invoke-RestMethod` (default agent,
  no headers, L 4378), then a Chrome-UA `Invoke-WebRequest` retry on the
  catch (L 4385-4400). `urlhealth.c` already mirrors this (simple
  `photonos-package-report/C` UA → Chrome fallback); the scraper did not.
  `pr_scrape_listing` now keeps the Chrome attempt as the PRIMARY (so every
  spec that already detects is byte-identical — it returns on the first
  attempt and never reaches the fallback) and adds a simple-UA fallback
  (`photonos-package-report/C`, no extra headers) only when the Chrome
  attempt fails or yields zero hrefs. Some autoindex hosts (e.g.
  `dist.schmorp.de/libev/Attic/`) serve the listing to the simple agent
  but not to Chrome — the same UA `urlhealth` used to get 200 on the file.
  An env-gated `PR_SCRAPE_DEBUG` stderr trace (URL, UA stage, http status,
  body len, href count) aids diagnosis; it never touches the `.prn`.
