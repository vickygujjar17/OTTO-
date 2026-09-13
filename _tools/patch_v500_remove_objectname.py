#!/usr/bin/env python3
"""
patch_v500_remove_objectname.py

Phase 1 cleanup helper: removes the now-dead `nb.objectName = "";`
initializations from COttoBlockManager.mqh after the `objectName` field was
removed from the SSniperBlock struct in OttoDefines.mqh.

Operates on bytes and preserves CRLF + UTF-8 exactly.
Creates a .bak backup before writing.
"""

import sys
import re

PATH = r"C:\Users\vivek\Downloads\cline local work\COttoBlockManager.mqh"

TARGET = re.compile(rb'([ \t]*nb\.objectName[ \t]*=[ \t]*"";[ \t]*\r\n)')

def main():
    with open(PATH, "rb") as fh:
        data = fh.read()

    before = data.count(b"objectName")

    # Drop the entire matched line (assignment + its CRLF).
    newdata = TARGET.sub(b"", data)

    after = newdata.count(b"objectName")

    # Safety: only line-removal should have happened; verify CRLF integrity
    def stats(b):
        crlf = b.count(b"\r\n")
        bare = b.count(b"\n") - crlf
        return crlf, bare

    c0, l0 = stats(data)
    c1, l1 = stats(newdata)

    print("objectName occurrences : %d -> %d" % (before, after))
    print("CRLF                   : %d -> %d" % (c0, c1))
    print("bare LF                : %d -> %d" % (l0, l1))
    print("bytes                  : %d -> %d" % (len(data), len(newdata)))

    if l1 != 0:
        print("ABORT: bare LF introduced")
        return 3
    if after != 0:
        print("ABORT: objectName references still present")
        return 4

    with open(PATH + ".bak", "wb") as fh:
        fh.write(data)
    with open(PATH, "wb") as fh:
        fh.write(newdata)

    print("OK: patched, backup written to %s.bak" % PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())