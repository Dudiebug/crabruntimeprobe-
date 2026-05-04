# Object Dump Inputs

Place Crab Champions UE4SS object dump files here.

If the dump is split into parts, copy every part into this folder before running
the parser. Missing a part can produce incomplete docs and unsafe assumptions.

Accepted input patterns for parser tooling:

- `*.txt`
- `*.part*`
- `*.md`

The parser is fail-soft, scans every supported input file, records unreadable
files as warnings, and preserves raw matched lines when formatting is unknown.
