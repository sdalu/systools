# systools

Small system tools in POSIX sh, for FreeBSD and Linux.

## Where things are

- `README.md` — the tools, what each needs, installing, known shortfalls
- `DESIGN.md` — why they are shaped so
- `HISTORY.md` — what was tried and abandoned
- `CHECKLIST.md` — what has to be true before a round here is done
- `bin/` — the tools; each one's header comment is a summary of it
- `man/` — one mdoc page per tool, the full reference; `make check`
  lints them and holds each page's options to its tool's `getopts`
- `tests/` — the suite: `tests/lib.sh` (helpers), `tests/run.sh`, one
  `t-*.sh` per tool, stand-ins for external tools in `tests/fake/`,
  recorded real output in `tests/data/`, and `tests/dav-server.rb`, the
  local DAV server `caldav` and `carddav` are tested against

## Gate

Gate: `make check && make tests` — `check` is preflight (parse, shellcheck,
the man pages) and runs none of the tools; `tests` runs them all against the stand-ins.

## Traps

- **A tool that calls a new external command makes the suite bail out**
  ("Bail out: X does not resolve to tests/fake/X") once it is added to
  the list in `tests/lib.sh` — and silently reaches the real one until it
  is. Add the stand-in and the list entry together.
- **`VAR=value func` does not reach the function's commands under
  FreeBSD sh**, and POSIX leaves it unspecified. In the scripts put the
  assignment on the command inside the function; in the tests `export`
  it and `unset` it after. A test written the other way passes for the
  wrong reason.
- **`run` sets `rc`, `out` and `err`** in the test's own shell. A test
  that keeps a path in `$out` has it replaced by the tool's output, and
  writes files named after that output into the current directory --
  the repository root, when run from there. Inside `( ... )` it sets
  them in the subshell only, and the checks after it read the run
  before.
- **Write a test file with the editor, not `cat <<EOF` in the shell.**
  Test files carry here-documents of their own; the outer one ends at
  their first `EOF`, and the rest of the file runs as shell.
- **FreeBSD sh's `command -v` takes one name.** `command -v a b` fails
  there, so a probe written that way decides wrongly -- one here made a
  test skip itself without saying why.
- **A check that depends on the host fails on the other system** —
  whether gcc exists, which `make` is GNU. Assert what the command run
  under the tool sees, not what the tool did on the way there.
