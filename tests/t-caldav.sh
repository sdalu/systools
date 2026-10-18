#!/bin/sh
# caldav: every command against a local DAV server (tests/dav-server.rb)
# -- calendars, list and its window, filter, limit, tasks and every
# calendar, show, add, set, edit and its conflict, import, delete,
# backup, props -- the credentials, --backup, --dry-run, --json, and
# the refusals, each checked to have changed nothing.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

if ! ruby_ready; then
    pass "skipped: no ruby 3.4 with nokogiri here"
    finish
    exit
fi

export TZ=UTC HOME="$tmp/home" EDITOR=false
unset CALDAV_USER CALDAV_PASSWORD EMAIL
mkdir -p "$HOME"

user=u@example.org
cals=$tmp/dav/dav/calendars/user/$user
mkdir -p "$cals/Default" "$cals/Work" "$cals/Tasks"
printf 'kind=calendar\ndisplayname=Personal\ncomponents=VEVENT,VTODO\n' \
    > "$cals/Default/.props"
printf 'kind=calendar\ndisplayname=Work\ncomponents=VEVENT\n' \
    > "$cals/Work/.props"
printf 'kind=calendar\ndisplayname=Tasks\ncomponents=VTODO\n' \
    > "$cals/Tasks/.props"
# event FILE UID SUMMARY DTSTART DTEND [LINE...] — a VEVENT in a file.
event() {
    ev_file=$1
    shift
    {
        printf 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\n'
        printf 'BEGIN:VEVENT\r\nUID:%s\r\nSUMMARY:%s\r\n' "$1" "$2"
        printf 'DTSTART%s\r\nDTEND%s\r\n' "$3" "$4"
        shift 4
        for line; do printf '%s\r\n' "$line"; done
        printf 'END:VEVENT\r\nEND:VCALENDAR\r\n'
    } > "$ev_file"
}
event "$cals/Default/dentist.ics" dentist-1 Dentist \
    :20261110T090000Z :20261110T100000Z 'LOCATION:Rue du Port'
event "$cals/Default/team.ics" team-1 'Team meeting' \
    :20261112T140000Z :20261112T150000Z 'CATEGORIES:Work'
event "$cals/Default/holiday.ics" holiday-1 Holiday \
    ';VALUE=DATE:20261224' ';VALUE=DATE:20261226'
event "$cals/Work/review.ics" review-1 Review \
    :20261111T100000Z :20261111T110000Z
printf '%s\r\n' BEGIN:VCALENDAR VERSION:2.0 BEGIN:VTODO UID:milk-1 \
    'SUMMARY:Buy milk' DUE:20261111T180000Z STATUS:NEEDS-ACTION \
    END:VTODO END:VCALENDAR > "$cals/Default/milk.ics"

dav_server "$tmp/dav"
url=http://127.0.0.1:$dav_port/dav/calendars/user/$user/Default/
cal() {
    : > "$dav_log"
    run caldav -u "$user" -p secret -U "$url" "$@"
}
# verbs: the verbs the server was asked, one line.
verbs() {
    awk '{ printf "%s%s", sep, $1; sep = " " }' "$dav_log"
}
nov='-f 2026-11-01 -t 2026-11-30'

# --- reading ---------------------------------------------------------------

run caldav -u "$user" -p secret -U "$url" calendars
check_eq "$out" "Default	Personal	VEVENT,VTODO
Tasks	Tasks	VTODO
Work	Work	VEVENT" "calendars: id, name and components"

# shellcheck disable=SC2086  # $nov is two options
cal $nov list
check_rc 0 "list: succeeds"
check_eq "$out" "2026-11-10 09:00-10:00	Dentist	dentist-1
2026-11-12 14:00-15:00	Team meeting	team-1" \
    "list: the events of the window, in order; the task left out"
check_in "$(cat "$dav_log")" "user=$user" "list: the user is sent"
cal -f 2026-12-01 -t 2026-12-31 list
check_eq "$out" "2026-12-24..2026-12-25	Holiday	holiday-1" \
    "list: an all-day event ends on its last day, inclusive"
# shellcheck disable=SC2086
cal $nov list work
check_eq "$out" "2026-11-12 14:00-15:00	Team meeting	team-1" \
    "list REGEX: matches the categories, any case"
# shellcheck disable=SC2086
cal $nov -N 1 list
check_eq "$out" "2026-11-10 09:00-10:00	Dentist	dentist-1" "-N 1: the first only"
# shellcheck disable=SC2086
cal $nov -A list
check_eq "$out" "Personal	2026-11-10 09:00-10:00	Dentist	dentist-1
Work	2026-11-11 10:00-11:00	Review	review-1
Personal	2026-11-12 14:00-15:00	Team meeting	team-1" \
    "-A: every calendar holding events, labelled, merged in order"
cal -T list
check_eq "$out" "2026-11-11 18:00	NEEDS-ACTION	Buy milk	milk-1" \
    "-T list: the tasks, every one without a window"
# shellcheck disable=SC2086
cal $nov -j list
check_rc 0 "-j list: succeeds"
# shellcheck disable=SC2016  # Ruby, not shell
check_eq "$(printf '%s' "$out" | ruby -rjson -e \
    'puts JSON.parse($stdin.read).map { it["summary"] }.join(",")')" \
    "Dentist,Team meeting" "-j list: a JSON array of the events"

cal show dentist-1
check_in "$out" "LOCATION:Rue du Port" "show UID: the event's iCalendar"
cal show 'dent'
check_in "$out" "UID:dentist-1" "show REGEX: one summary matched"
cal show 'e'
check_rc 1 "show, a regex matching several: exit 1"
check_in "$err" "e is ambiguous" "show, several: said so"
check_in "$err" "dentist-1" "show, several: listed"
cal show nothing-like-it
check_rc 1 "show, no match: exit 1"
check_in "$err" "no event matches nothing-like-it" "show, no match: said so"

# --- changing --------------------------------------------------------------

cal add -S Lunch --start '2026-11-13 12:00' --duration 1h30m -l Canteen
check_rc 0 "add: succeeds"
check_in "$out" "created " "add: reported"
new=$(grep -l '^SUMMARY:Lunch' "$cals/Default"/*.ics)
check_in "$(cat "$new")" "DTSTART;TZID=UTC:20261113T120000" \
    "add: the start, in the local zone"
check_in "$(cat "$new")" "DTEND;TZID=UTC:20261113T133000" \
    "add: --duration gives the end"
check_in "$(cat "$new")" "LOCATION:Canteen" "add: -l"
check_eq "${new##*/}" "$(sed -n 's/^UID:\(.*\)\r$/\1/p' "$new").ics" \
    "add: stored under its new UID"
check_in "$(cat "$dav_log")" "PUT" "add: stored"
check_in "$(cat "$dav_log")" "if-none-match=*" "add: create only"

cal -n add -S Dry --start '2026-11-14 12:00'
check_in "$out" "SUMMARY:Dry" "-n add: the event printed"
check_not_in "$(verbs)" "PUT" "-n add: nothing stored"

cal add -T -S 'Call back' --due '2026-11-15 17:00'
check_rc 0 "add -T: a task"
check_in "$(cat "$cals/Default"/*.ics)" "DUE;TZID=UTC:20261115T170000" \
    "add -T: --due"

cal -B"$tmp/kept" set dentist-1 -l 'Rue Neuve' --alarm 15m
check_rc 0 "set: succeeds"
check_in "$(cat "$cals/Default/dentist.ics")" "LOCATION:Rue Neuve" \
    "set -l: the location replaced"
check_not_in "$(cat "$cals/Default/dentist.ics")" "Rue du Port" \
    "set -l: the old location gone"
check_in "$(cat "$cals/Default/dentist.ics")" "TRIGGER:-PT15M" \
    "set --alarm: a reminder"
check_not_in "$(cat "$cals/Default/dentist.ics")" "SEQUENCE:" \
    "set with no new time: SEQUENCE left alone"
check_in "$(cat "$dav_log")" 'if-match="' "set: updates only that version"
check_in "$(cat "$tmp/kept"/dentist-1-*.ics)" "Rue du Port" \
    "-B: the server's version kept before the change"

cal set dentist-1 --start '2026-11-10 11:00'
check_in "$(cat "$cals/Default/dentist.ics")" "DTEND;TZID=UTC:20261110T120000" \
    "set --start alone: the length kept"
check_in "$(cat "$cals/Default/dentist.ics")" "SEQUENCE:1" \
    "set --start: SEQUENCE raised, for attendees"

saved=$(cat "$cals/Default/dentist.ics")
cal set dentist-1 --end '2026-11-10 08:00'
check_rc 2 "set, an end before the start: exit 2"
check_in "$err" "is not after the start" "an end before the start: said so"
check_eq "$(cat "$cals/Default/dentist.ics")" "$saved" \
    "an end before the start: nothing changed"
check_not_in "$(verbs)" "PUT" "an end before the start: nothing stored"

cal set team-1 -d CATEGORIES -a 'CATEGORIES:Board'
check_in "$(cat "$cals/Default/team.ics")" "CATEGORIES:Board" "set -d -a: added"
check_not_in "$(cat "$cals/Default/team.ics")" "CATEGORIES:Work" \
    "set -d: removed"

cat > "$tmp/ed-rename" <<'EOF'
#!/bin/sh
awk '{ sub(/^SUMMARY:Team meeting/, "SUMMARY:Team sync"); print }' "$1" \
    > "$1.new" && mv -f -- "$1.new" "$1"
EOF
EDITOR="sh $tmp/ed-rename" cal edit team-1
check_rc 0 "edit: succeeds"
check_in "$(cat "$cals/Default/team.ics")" "SUMMARY:Team sync" \
    "edit: the editor's change stored"
EDITOR=true cal edit team-1
check_in "$err" "unchanged" "edit, nothing changed: said so"
check_not_in "$(verbs)" "PUT" "edit, nothing changed: nothing stored"

# An editor that also changes the event on the server, as another
# client would meanwhile: the stale version must not be overwritten.
cat > "$tmp/ed-race" <<EOF
#!/bin/sh
printf 'X-OTHER:1\r\n' >> "$cals/Default/team.ics"
sh "$tmp/ed-rename" "\$1"
EOF
awk '{ sub(/SUMMARY:Team sync/, "SUMMARY:Team meeting"); print }' \
    "$cals/Default/team.ics" > "$tmp/t" && mv "$tmp/t" "$cals/Default/team.ics"
EDITOR="sh $tmp/ed-race" cal edit team-1
check_rc 1 "edit, changed on the server meanwhile: exit 1"
check_in "$err" "the event changed on the server; your edits are kept in" \
    "edit, a conflict: said so, and the copy named"
kept=$(printf '%s\n' "$err" | sed -n 's/.*kept in //p')
check_in "$(cat "$kept" 2> /dev/null)" "SUMMARY:Team sync" \
    "edit, a conflict: the edits kept"
check_in "$(cat "$cals/Default/team.ics")" "X-OTHER:1" \
    "edit, a conflict: the server's version untouched"

event "$tmp/import.ics" dentist-1 'Dentist (moved)' \
    :20261117T090000Z :20261117T100000Z
event "$tmp/import-new.ics" gym-1 Gym :20261118T070000Z :20261118T080000Z
cal import "$tmp/import.ics" "$tmp/import-new.ics"
check_rc 0 "import: succeeds"
check_in "$(cat "$cals/Default/dentist.ics")" "SUMMARY:Dentist (moved)" \
    "import: a known UID updates its event"
check_in "$(cat "$cals/Default"/*.ics)" "UID:gym-1" "import: a new UID creates"

cal delete gym
check_rc 0 "delete: succeeds"
check_not_in "$(cat "$cals/Default"/*.ics)" "UID:gym-1" "delete: gone"
check_in "$(cat "$dav_log")" 'DELETE' "delete: asked"

cd -- "$tmp" || exit 1
run caldav -u "$user" -p secret -U "$url" backup
cd -- "$top" || exit 1
backup=$(ls "$tmp"/Default-*.ics 2> /dev/null)
check_in "$err" "events saved to" "backup: said so"
check_eq "$(grep -c '^BEGIN:VCALENDAR' "$backup")" 1 \
    "backup: one VCALENDAR"
check_in "$(cat "$backup")" "UID:holiday-1" "backup: every event, any date"
cal backup -
check_in "$out" "UID:dentist-1" "backup -: to stdout"

cal props
check_eq "$out" "$(printf 'name\tPersonal\ncolor\t\ndescription\t')" \
    "props: name, colour and description, unset ones empty"
cal props --name Home --color 00ff00 -D 'Mine'
check_in "$out" "name	Home" "props --name: set"
check_in "$out" "color	#00ff00" "props --color: set, with its #"
check_in "$(cat "$cals/Default/.props")" "calendar-description=Mine" \
    "props -D: set"
cal props -D ''
check_not_in "$(cat "$cals/Default/.props")" "calendar-description" \
    "props -D '': removed"
cal props --color red
check_rc 2 "props --color red: exit 2"

# --- credentials -----------------------------------------------------------

printf 'machine 127.0.0.1 login netrc@example.org password fromfile\n' \
    > "$HOME/.authinfo"
: > "$dav_log"
run caldav -U "$url" calendars
check_rc 0 "an authinfo entry: succeeds"
check_in "$(cat "$dav_log")" "user=netrc@example.org" \
    "an authinfo entry: the login of the URL's host"
export CALDAV_USER=env@example.org CALDAV_PASSWORD=envpw
: > "$dav_log"
run caldav -U "$url" calendars
check_in "$(cat "$dav_log")" "user=env@example.org" \
    "CALDAV_USER: before the authinfo entry"
unset CALDAV_USER CALDAV_PASSWORD
rm -f -- "$HOME/.authinfo"
run caldav -U "$url" calendars < /dev/null
check_rc 1 "no user anywhere: exit 1"
check_in "$err" "no user given" "no user anywhere: said so"
printf 'machine mail.example.org login other@example.org password x\n' \
    > "$HOME/.authinfo"
: > "$dav_log"
run caldav -U "$url" calendars < /dev/null
check_rc 1 "an entry for another host only: exit 1"
check_in "$err" "an entry for 127.0.0.1 in" \
    "an entry for another host only: the host looked for named"
check_eq "$(cat "$dav_log")" "" "an entry for another host only: nothing asked"
run caldav calendars < /dev/null
check_rc 1 "no -U and no user: exit 1"
check_in "$err" "no user given (--user, CALDAV_USER or EMAIL), and no --url" \
    "no -U and no user: said so, before looking up any server"
rm -f -- "$HOME/.authinfo"

# $EMAIL: after CALDAV_USER and the entry's login, before nothing else.
export EMAIL=mail@example.org CALDAV_PASSWORD=envpw
: > "$dav_log"
run caldav -U "$url" calendars
check_rc 0 "EMAIL: succeeds"
check_in "$(cat "$dav_log")" "user=mail@example.org" \
    "EMAIL: the user when nothing else names one"
printf 'machine 127.0.0.1 login netrc@example.org password fromfile\n' \
    > "$HOME/.authinfo"
: > "$dav_log"
run caldav -U "$url" calendars
check_in "$(cat "$dav_log")" "user=netrc@example.org" \
    "EMAIL: after the login of the URL host's entry"
rm -f -- "$HOME/.authinfo"
export CALDAV_USER=env@example.org
: > "$dav_log"
run caldav -U "$url" calendars
check_in "$(cat "$dav_log")" "user=env@example.org" "EMAIL: after CALDAV_USER"
unset CALDAV_USER
export EMAIL=nodomain
run caldav calendars < /dev/null
check_rc 1 "EMAIL, no -U: the server looked up from it"
check_in "$err" "user has no domain" \
    "EMAIL, no -U: its domain is where the server is looked for"
export EMAIL=
run caldav calendars < /dev/null
check_in "$err" "no user given" "an empty EMAIL: no user"
unset EMAIL CALDAV_PASSWORD

run caldav -u "$user" -p secret -U "http://127.0.0.1:1/x/Default/" calendars
check_rc 1 "nothing listening: exit 1"

# --- refusals --------------------------------------------------------------

for args in '' 'bogus' '--nope list' '-N 0 list' 'add' 'add -S x' \
    'show' 'import'; do
    # shellcheck disable=SC2086  # each case is a word list
    cal $args
    check_rc 2 "refuses [$args] as a usage error"
    check_not_in "$(verbs)" "PUT" "refuses [$args]: nothing stored"
done
run caldav -h
check_rc 0 "-h: exit 0"
check_in "$out" "Usage: caldav" "-h: the usage"

finish
