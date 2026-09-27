# ADR-0003 — The base declares its kernel-specific regions as slots

Status: accepted, implemented
Date: 2026-09-27
Feature: [FRD-001](../features/kernel-wrapper.md)

## Context

The Python generator located its edits with 25 anchors: exact strings, each asserted to occur a
given number of times. An anchor is a guess about the base made from outside it. When the base
changes, the anchor fails (good) but says nothing about what the region now means (bad), and a
region that is kernel-specific but carries no anchor passes silently.

Three ways to find the kernel-specific parts of the base were weighed:

1. Anchors in the tool (the Python approach, ported).
2. A template: the base becomes a template file with placeholders.
3. Slots: the base marks its own kernel-specific regions with comment markers.

## Decision

Slots. The base carries `# @sharukhan-wrapper kernel=… userland=… native-series=…` and nine
`# @sharukhan-slot <name> begin|end` pairs. The tool knows the slot names and has one typed renderer
per slot. Everything outside the slots is carried over and renamed by computed identity, and the
rename is followed by collision, leak and leftover checks (FRD-001 KW-9..KW-12).

## Why not the others

- Anchors put knowledge of the base into the tool and fail late and vaguely.
- A template stops being a runnable script. The base is a wrapper people run every day; it must stay
  one. Placeholders can also survive substitution, which is exactly the defect class REQ-3 forbids.
- Slot markers are comments to both `sh` and Python, so the base runs unchanged, and the base author
  sees in the file which regions a derivation replaces.

## Consequences

- Moving code into or out of a slot is a reviewed change to the base.
- The base must be version-neutral outside its slots, except for identity strings that the renames
  cover (ADR-0007 made it so).
- A slot missing, duplicated or unknown is a typed error ("expected 1, found 0/2").
