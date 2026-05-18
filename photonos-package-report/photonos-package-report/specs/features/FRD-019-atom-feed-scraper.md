# FRD-019-atom-feed-scraper: Atom-feed tag-list scraper

**Feature ID**: FRD-019-atom-feed-scraper
**Related PRD Requirements**: REQ-11
**Related ADRs**: ADR-0001, ADR-0002, ADR-0006
**PS source range**: photonos-package-report.ps1 L 3770-3996 (SourceTagURL overrides), L 4258-4283 (atom feed entry points)
**Status**: Draft
**Last updated**: 2026-05-18

---

## 1. Overview

PS dispatches many specs through `gitlab.freedesktop.org/<group>/<proj>/-/tags?format=atom`
or `gitlab.com/<group>/<proj>/-/tags?format=atom` URLs to read tag names
from an Atom XML feed. ~30+ specs use this pattern (dbus, dbus-python,
fontconfig, gstreamer, libdrm, mesa, pixman, ModemManager, libmbim,
libqmi, libXi, libXcomposite, libXdamage, libXdmcp, libXext,
libXfixes, libXfont2, libXrandr, libXrender, libXxf86vm, ...).

C's existing `pr_scrape_listing()` (FRD-018) only parses HTML
`<a href>` values. Atom feeds use:

```xml
<feed>
  <entry><title>v1.2.3</title>...</entry>
  <entry><title>v1.2.2</title>...</entry>
  ...
</feed>
```

So those ~30 specs return zero candidates from the HTML href extractor.
They contribute to the col[5 6 7 9 10] residual bucket on every branch
(the same bucket as gnome/sourceforge scraper-fetch failures, but with
a different root cause: format mismatch rather than missing per-host
listing logic).

## 2. Functional requirements

### 2.1 Atom feed parser

New module `src/atom_feed.c` + `include/pr_atom_feed.h`:

```c
int pr_scrape_atom_feed(const char *url,
                        char ***out_names,
                        size_t *out_n);
```

- libcurl GET (same UA + headers as `pr_scrape_listing`).
- PCRE2 match `<title>([^<]*)</title>` inside each `<entry>...</entry>`.
  - Skip the feed-level `<title>` (top of the feed). One approach:
    consume the first `<title>` outside any `<entry>`, then enable
    capture only inside `<entry>...</entry>`.
- Decode `&amp;` / `&lt;` / `&gt;` / `&quot;` / `&apos;` entities
  in the captured title string (atom titles are XML-escaped).
- Return malloc'd names array; caller frees via existing
  `pr_git_tags_free` helper.

### 2.2 Dispatcher: per-spec SourceTagURL overrides

New table-driven helper in `src/per_spec_strip.c` (or new module
`src/per_spec_url.c`) keyed on spec name: spec → SourceTagURL override.
PS L 3770-3813 covers gitlab-tag-atom specs; PS L 3961-3996 covers
kernel.org cgit specs (HTML format, FRD-018 territory).

For atom-feed specs:

```c
const char *pr_per_spec_source_tag_url(const char *spec_name);
```

Returns the override URL or NULL.

### 2.3 Wiring

`src/check_urlhealth.c` non-git scraper path:

1. Compute `parent = dirname(state.Source0)` (existing).
2. **NEW**: check `pr_per_spec_source_tag_url(task->Spec)`; if non-NULL,
   override `parent` with the per-spec URL.
3. **NEW**: if the resolved URL ends with `?format=atom` (or matches
   a per-host atom-detector), call `pr_scrape_atom_feed`; else
   `pr_scrape_listing` (existing).
4. Apply the existing filter pipeline (M22-M29) to the names list.

## 3. Bit-identical assertions

- For atom-feed specs, the latest-tag selection after the filter
  pipeline matches PS byte-for-byte on cols 5 (UpdateAvailable),
  6 (UpdateURL), 9 (SHAName), 10 (UpdateDownloadName).
- Per-spec SourceTagURL override produces the same URL as PS's
  L 3770-3813 dispatcher.
- Atom XML entity decoding matches PS's `Invoke-RestMethod` + `.name`
  property which decodes XML entities automatically.

## 4. Acceptance tests

- Unit: feed a canned atom XML to `pr_scrape_atom_feed`; assert N
  titles extracted with entity decoding correct.
- Integration: 5 representative atom-feed specs (dbus-python,
  fontconfig, gstreamer, libdrm, mesa) — strict cols 5/6/9/10 match
  PS on the snapshot fixture.

## 5. Dependencies

- libcurl (already required).
- PCRE2 (already required).
- Source0LookupData (FRD-003) — per-spec URL override table integrates
  with the existing lookup or extends it.

## 6. Open questions

1. **Per-host atom detection** — should the dispatcher check URL
   suffix (`?format=atom`) or per-host? PS hard-codes specific
   gitlab.freedesktop.org URLs. C could be smarter (any URL ending
   `?format=atom` → atom parser) but might over-match.
2. **Pagination** — gitlab atom feeds default to one page (20-30
   entries). PS L 2790-2814 has a multi-page loop. Do we need that
   for tag-list URLs, or do recent tags suffice for "latest"
   detection? Open.
3. **Entity decoding scope** — minimal set vs. full XML 1.0
   entity table. The PS tags rarely contain XML-escaped chars; minimal
   set (the 5 standard) is probably enough.
4. **Per-spec hook integration** — some atom-feed specs ALSO have
   `$replace +=` strip tokens in the L 2839 switch. Those are
   already covered by M27. So new wiring just adds the URL override +
   parser dispatch; M27 chain handles the per-spec tokens.

## 7. Rollout plan

1. **PR-A**: this FRD draft → Accepted (no code change).
2. **PR-B**: `pr_scrape_atom_feed` + unit test (no integration).
3. **PR-C**: per-spec SourceTagURL override table for the gitlab atom
   feeds (10-15 specs at first).
4. **PR-D**: wire dispatcher into `check_urlhealth.c`.
5. **PR-E**: validate on workflow run; iterate on per-host quirks.
6. Future PRs: extend coverage (gitlab.com tags, atom feeds from
   other hosts).
