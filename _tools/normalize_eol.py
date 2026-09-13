#!/usr/bin/env python3
"""
normalize_eol.py -- OTTO EA build tooling

Normalizes MQL5 source line endings to strict CRLF WITHOUT touching content
bytes. Operates purely on bytes so UTF-8 (including any mojibake) survives
byte-for-byte.

Usage:
    python normalize_eol.py <directory>          # report + rewrite to CRLF
    python normalize_eol.py <directory> --check  # report only, no writes
"""

import sys
import os
import glob

EXTS = (".mq5", ".mqh")


def analyze(data: bytes):
    crlf = data.count(b"\r\n")
    bare_lf = data.count(b"\n") - crlf
    bare_cr = data.count(b"\r") - crlf
    return crlf, bare_lf, bare_cr


def to_crlf(data: bytes) -> bytes:
    # 1) collapse any existing CRLF to LF, 2) expand all LF to CRLF.
    # This also fixes stray bare CR by leaving them only if not part of CRLF.
    data = data.replace(b"\r\n", b"\n")
    data = data.replace(b"\n", b"\r\n")
    return data


def nonascii_count(data: bytes) -> int:
    return sum(1 for b in data if b > 127)


def main():
    if len(sys.argv) < 2:
        print("usage: normalize_eol.py <directory> [--check]")
        return 2

    root = sys.argv[1]
    check_only = "--check" in sys.argv

    files = []
    for ext in EXTS:
        files.extend(glob.glob(os.path.join(root, "*" + ext)))
    files.sort()

    if not files:
        print("no .mq5/.mqh files found in %s" % root)
        return 1

    print("=" * 78)
    print("LINE-ENDING NORMALIZATION  root=%s  mode=%s"
          % (root, "CHECK-ONLY" if check_only else "REWRITE"))
    print("=" * 78)

    changed = 0
    for path in files:
        with open(path, "rb") as fh:
            data = fh.read()

        crlf, bare_lf, bare_cr = analyze(data)
        na_before = nonascii_count(data)
        fixed = to_crlf(data)
        na_after = nonascii_count(fixed)

        if data != fixed:
            changed += 1
            status = "REWRITE"
        else:
            status = "ok"

        print("%-28s CRLF=%-6d bareLF=%-5d bareCR=%-3d bytes=%-7d "
              "nonASCII=%-6d -> %s"
              % (os.path.basename(path), crlf, bare_lf, bare_cr,
                 len(data), na_before, status))

        if na_before != na_after:
            print("  !! non-ASCII byte count changed (%d -> %d) -- ABORT"
                  % (na_before, na_after))
            return 3

        if data != fixed and not check_only:
            with open(path, "wb") as fh:
                fh.write(fixed)

    print("-" * 78)
    print("files=%d  rewritten=%d" % (len(files), changed if not check_only else 0))

    # Post-verification
    if not check_only:
        print("=" * 78)
        print("POST-VERIFICATION")
        print("=" * 78)
        bad = 0
        for path in files:
            with open(path, "rb") as fh:
                data = fh.read()
            crlf, bare_lf, bare_cr = analyze(data)
            ok = (bare_lf == 0 and bare_cr == 0 and crlf > 0)
            if not ok:
                bad += 1
            print("%-28s CRLF=%-6d bareLF=%-4d bareCR=%-3d %s"
                  % (os.path.basename(path), crlf, bare_lf, bare_cr,
                     "OK" if ok else "FAIL"))
        print("-" * 78)
        print("verification failures: %d" % bad)
        return 1 if bad else 0

    return 0


if __name__ == "__main__":
    sys.exit(main())