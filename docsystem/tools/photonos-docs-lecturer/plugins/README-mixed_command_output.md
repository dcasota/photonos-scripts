# Mixed Command Output Plugin

**Version:** 2.0.0  
**FIX_ID:** 0 (Detection Only)  
**Requires LLM:** No

## Description

Detects code blocks that mix commands with their output.

## Issues Detected

1. **Commands with output** - Same block has both runnable commands and output

## Why Detection Only

Mixed command/output can be intentional:
- Show expected results
- Document interactive sessions
- Provide context

Separation requires understanding what is command vs output.

## Example

```bash
$ ls -la
total 48
drwxr-xr-x  5 root root 4096 Dec 10 10:00 .
-rw-r--r--  1 root root 1234 Dec 10 09:00 file.txt

$ cat file.txt
Hello World
```

The commands (`ls -la`, `cat file.txt`) are mixed with their output.

## Configuration

No configuration required.
