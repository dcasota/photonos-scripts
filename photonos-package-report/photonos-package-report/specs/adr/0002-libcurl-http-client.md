# ADR-0002: HTTP client — libcurl

**Status**: Accepted
**Date**: 2026-05-12

## Context

The PS script uses `[System.Net.HttpWebRequest]::Create($url)`, `Invoke-WebRequest`, and `Invoke-RestMethod` against 25+ distinct hosts with idiosyncratic requirements: HEAD method, Mozilla User-Agent, per-host `Referer` headers (netfilter.org family at L 1480-1500), TLS 1.2 floor (L 5030), and timeout = 120 s.

## Decision

**libcurl 8.x** via `libcurl-devel` Photon RPM.

## Rationale

- Native support for every option the PS script uses: `CURLOPT_NOBODY` (HEAD), `CURLOPT_USERAGENT`, `CURLOPT_REFERER`, `CURLOPT_TIMEOUT`, `CURLOPT_SSLVERSION = CURL_SSLVERSION_TLSv1_2`.
- Multi-handle interface allows in-process parallelism if needed later (not in v1 — v1 keeps thread-per-task per ADR-0004).
- Connection reuse via `CURLM_OPT_*` reduces re-handshake overhead on hosts that get probed many times (github.com, kernel.org).

## Consequences

- One `CURL *` per worker thread, reset between calls (`curl_easy_reset`); shared `CURLSH *` for DNS/SSL session cache.
- Per-host Referer/User-Agent overrides ported as a static lookup table in `http_client.c`.
- Error reporting via `CURLcode` mapped 1:1 to the PS catch-block status codes the script reads from `$_.Exception.Response.StatusCode.value__`.

## Considered alternatives

- **wget shell-out**: simpler but loses programmatic access to HTTP status codes; tarball-only response handling.
- **rolled HTTP via openssl**: maintenance nightmare.
