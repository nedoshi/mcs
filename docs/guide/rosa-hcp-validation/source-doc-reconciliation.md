# Source document reconciliation

**Status (2026-09-17):** Both Google Docs returned **sign-in required** for WebFetch, `export?format=txt`, and unauthenticated `curl`. No references to document IDs `1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM` or `193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4` exist in this repository.

| Document | URL | Access |
|----------|-----|--------|
| Source doc A | [1ds3_F0GNj4…](https://docs.google.com/document/d/1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM/edit) | **Not readable** (private) |
| Source doc B | [193yRGltNtK2…](https://docs.google.com/document/d/193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4/edit) | **Not readable** (private) |

## How to align this folder with the Google Docs

1. Export each doc (File → Download → Plain text) or paste sections into a scratch file.
2. Map each **named test case** in the docs to a file in this directory (or split/merge files).
3. Update the pass/fail matrix in [README.md](README.md) with the **exact IDs and titles** from the docs.
4. Remove or rewrite sections marked **Inferred from repo** where the doc supersedes them.
5. Record execution dates in [validation-report.md](validation-report.md).

Until reconciliation completes, treat numbered procedures here as **repo-derived validation patterns**, not authoritative copies of the Google Doc test catalog.
