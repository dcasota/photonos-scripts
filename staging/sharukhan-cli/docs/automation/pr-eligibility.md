# PR eligibility: is a PR still needed?

`sharukhan pr-eligibility` answers, per PR, whether the defects the PR fixes
are still in the base, in every copy of the PR's package. It writes one table
per PR.

```
sharukhan pr-eligibility                       # every PR in the data, on the release branch
sharukhan pr-eligibility --pr 22 --pr 87       # these PRs
sharukhan pr-eligibility --rev 4f6931f35f      # another base, or a sync candidate
sharukhan pr-eligibility --out report.md       # written atomically instead of printed
sharukhan pr-eligibility --defects edited.json # an edit of the data under test
```

## Why not "it passes without the PR"

A guest that installs, boots and passes its checks without a PR does not show
that the PR is unneeded. A dangling udev rule only logs a line, a file owned
by two packages shows only when one is removed, and a DHCP fix matters only on
a network that triggers it. So the question is asked of the defect itself: is
the faulty content still in the base, or is the fix already in the source the
base builds from?

## Copies

Photon 5.0 keeps one spec directory per subrelease range: `SPECS/90/systemd`
(subrelease 90 and below), `SPECS/91/systemd` (91-92) and `SPECS/systemd`
(93 and later), each with its own Version, patches and `config.yaml`. The
command finds every `SPECS/<package>` and `SPECS/<NN>/<package>` at the base
and reads each one's `%global build_if`. A PR's `subreleases` scope keeps the
copies it is about. The others are listed under "outside the PR's
subreleases", because another PR may own them; #92, for example, covers
`SPECS/90/systemd`.

## Probes

Each defect in `config/pr-defects.json` has one or more probes, and every
probe runs on every copy in scope:

| Probe | Looks at | Verdicts |
|---|---|---|
| `file` | lines of a file of the copy's spec directory: `present_if_all` patterns all there, `present_if_none` patterns none there; `applies_if` patterns must be there, or the defect is not applicable | present / absent / not applicable |
| `upstream` | full SHAs of the upstream fix commits, against the commit the copy's source archive is made from (`config.yaml` `commit_id`, history fetched from `repo_url` into `$MC_WORK/pr-eligibility`): an ancestor, a `(cherry picked from commit <sha>)` trailer in the source's history, or a patch the spec lists whose header names the SHA | fixed upstream / absent (carried by the copy's patches) / present |
| `upstream-file` | a file of that source, for the fixed code | fixed upstream, or undecided: a miss says nothing about the copy's own patches |
| `series` | the copy's `%prep` with `defines` (a build variant, e.g. `STIG_HARDEN=1`): `rpmspec -P` in the builder, `expect_patch` among the expanded patches, every patch applied at fuzz 0 to the source archive, sha512-checked against `config.yaml` (from the build root's SOURCES, or downloaded into the cache) | present (does not expand, unreachable, a patch missing or not applying) / absent |
| `rpm-overlap` | two packages of the gate's baseline build (`$MC_WORK/baseline-root/<release>/stage/RPMS`), only if their name-version-release is exactly the copy's: a build of other code is no evidence | present / absent / unknown |

A pattern is exactly one of `line` (the whole line), `prefix` or `contains`,
compared with trailing blanks ignored. Upstream SHAs must be full 40-hex: an
abbreviation cannot be fetched, and it can become ambiguous.

The probes of one defect on one copy combine as follows:

- **not applicable:** any probe that finds the defect's subject missing makes the defect not applicable.
- **contradiction:** "present" from one probe and "fixed upstream" from another is reported as a contradiction, never settled by the order of the probes.
- **otherwise:** present, then fixed, then absent.

## Reading the result

- **Still needed in:** at least one copy in scope has a defect present.
- **No defect present in any copy:** the PR's own symptom is gone on this base. Closing the PR is the user's decision, never the command's.
- **Undecided:** no defect is shown present, but a probe could not decide; the table shows which.

The last column is the guest symptom record. For each defect's
`symptom_check`, it counts pass and fail over every stored run, with the date
of the last failure. It is shown beside the verdicts, not used to make them:
it says that the symptom was seen, not on which copy.

Running the command on a sync candidate's head, with `--rev`, checks a port. When every
defect reads absent or fixed there, the port carries every fix.

## The data

`config/pr-defects.json` is compiled in; `SHARUKHAN_PR_DEFECTS` or `--defects`
names an edited copy. Each PR entry has `pr`, `package`, `title`, an optional
`subreleases` `{ "from": N, "to": M }`, and `defects`. Each defect has `id`,
`summary`, an optional `symptom_check` (a check id of `check-prs.tsv`) and
`probes`. The parser refuses repeated PRs or defect ids, empty probe lists, a
pattern with no or two kinds, abbreviated SHAs, paths that leave the spec
directory, and an empty subrelease scope.

Write the fix commits from the upstream commits themselves, not from a patch
header's prose. A header that says "Follow-up for <sha>" names the commit
that *introduced* the problem. That commit is usually in the base, and listing
it as a fix reads as a fix that is half there.
