# What was tried

Approaches taken and abandoned, with what settled each. An entry leaves
when the question it closes can no longer be asked.


## Shipping the tools as a gem

The tools were first packaged as a Ruby gem whose gemspec listed every
file of `bin/` as an executable. RubyGems does not install an executable
itself: it writes a Ruby wrapper that `load`s it (`app_script_text` in
`rubygems/installer.rb`, which emits
`load Gem.activate_bin_path(...)`, RubyGems 4.0.16). A `#!/bin/sh`
script installed that way is parsed as Ruby and fails on its first line,
so a gem can carry only Ruby tools. `make install` replaced it.
Re-proposing a gem means Ruby-only tools, or every user installing with
`--no-wrappers`.


## Ruby implementations

`pushover`, `zfs-snapshot` and `zfs-prune-snapshots` were Ruby, the last
two with the `pastel`, `tty-logger` and `tty-spinner` gems for their
output. Every host running them needed Ruby and those gems, installed
where the user cron runs as would find them. They were rewritten in sh,
and the spinner and colours became plain `-v` lines.


## Expiring one six-month date per run

`zfs-snapshot` once destroyed exactly the snapshot dated six months
before today, computed with Ruby's `Date#prev_month(6)`. That method
clamps the day to the target month, so 2026-02-28 gave 2025-08-28 and
2026-03-01 gave 2025-09-01: no run ever named 2025-08-29, 08-30 or 08-31,
and a Sunday snapshot on one of those days was kept forever. The same
holds every year for each day the month six months later lacks:
03-31, 05-31, 08-29 to 08-31, 10-31 and 12-31. Each run now expires every
date the six-month mark passed since the day before;
`tests/t-zfs-snapshot.sh` ("2026-03-01: 08-29 through 09-01 expire")
fails when the loop is put back to a single date.
