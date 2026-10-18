#!/bin/sh
# carddav: every command against a local DAV server (tests/dav-server.rb)
# -- books, list and its filter and every book, show, add, set, edit and
# its conflict, import, delete, backup and backup -A -- the credentials,
# --backup, --dry-run, --json, and the refusals, each checked to have
# changed nothing.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

if ! ruby_ready; then
    pass "skipped: no ruby 3.4 with nokogiri here"
    finish
    exit
fi

export TZ=UTC HOME="$tmp/home" EDITOR=false
unset CARDDAV_USER CARDDAV_PASSWORD EMAIL
mkdir -p "$HOME"

user=u@example.org
books=$tmp/dav/dav/addressbooks/user/$user
mkdir -p "$books/Default" "$books/Work"
printf 'kind=addressbook\ndisplayname=Personal\n' > "$books/Default/.props"
printf 'kind=addressbook\ndisplayname=Colleagues\n' > "$books/Work/.props"
# card FILE LINE... — a vCard 3.0 of those lines in a file.
card() {
    card_file=$1
    shift
    {
        printf 'BEGIN:VCARD\r\nVERSION:3.0\r\n'
        for line; do printf '%s\r\n' "$line"; done
        printf 'END:VCARD\r\n'
    } > "$card_file"
}
card "$books/Default/ada.vcf" UID:ada-1 'FN:Ada Lovelace' \
    'N:Lovelace;Ada;;;' 'EMAIL;TYPE=home:ada@example.org' \
    'NICKNAME:Countess'
card "$books/Default/alan.vcf" UID:alan-1 'FN:Alan Turing' \
    'N:Turing;Alan;;;' 'EMAIL;TYPE=work:alan@example.org' 'TEL:+44 1'
card "$books/Work/grace.vcf" UID:grace-1 'FN:Grace Hopper' \
    'N:Hopper;Grace;;;' 'ORG:Navy'

dav_server "$tmp/dav"
url=http://127.0.0.1:$dav_port/dav/addressbooks/user/$user/Default/
dav() {
    : > "$dav_log"
    run carddav -u "$user" -p secret -U "$url" "$@"
}
verbs() {
    awk '{ printf "%s%s", sep, $1; sep = " " }' "$dav_log"
}

# --- reading ---------------------------------------------------------------

dav books
check_eq "$out" "Default	Personal
Work	Colleagues" "books: id and name"

dav list
check_rc 0 "list: succeeds"
check_eq "$out" "ada-1	Ada Lovelace	ada@example.org
alan-1	Alan Turing	alan@example.org" "list: UID, name and emails, by name"
dav list countess
check_eq "$out" "ada-1	Ada Lovelace	ada@example.org" \
    "list REGEX: matches the nickname, any case"
dav -A list
check_eq "$out" "Personal	ada-1	Ada Lovelace	ada@example.org
Personal	alan-1	Alan Turing	alan@example.org
Colleagues	grace-1	Grace Hopper	" "-A list: every book, its name first"
dav -j list
# shellcheck disable=SC2016  # Ruby, not shell
check_eq "$(printf '%s' "$out" | ruby -rjson -e \
    'puts JSON.parse($stdin.read).map { it["fn"] }.join(",")')" \
    "Ada Lovelace,Alan Turing" "-j list: a JSON array of the contacts"

dav show alan@example
check_in "$out" "TEL:+44 1" "show REGEX: matched by email"
dav show a
check_rc 1 "show, a regex matching several: exit 1"
check_in "$err" "a is ambiguous" "show, several: said so"
dav show nobody
check_rc 1 "show, no match: exit 1"
check_in "$err" "no contact matches nobody" "show, no match: said so"

# --- changing --------------------------------------------------------------

dav add --fn 'Jean-Paul Sartre' -e jp@example.org -t '+33 1' -o 'Les Temps'
check_rc 0 "add: succeeds"
new=$(grep -l '^FN:Jean-Paul Sartre' "$books/Default"/*.vcf)
check_in "$(cat "$new")" "N:Sartre;Jean-Paul;;;" "add: N made from --fn"
check_in "$(cat "$new")" "EMAIL;TYPE=home:jp@example.org" "add -e"
check_in "$(cat "$new")" "TEL;TYPE=cell:+33 1" "add -t"
check_in "$(cat "$new")" "ORG:Les Temps" "add -o"
check_in "$(cat "$dav_log")" "if-none-match=*" "add: create only"

dav -n add --fn 'Dry Run'
check_in "$out" "FN:Dry Run" "-n add: the card printed"
check_not_in "$(verbs)" "PUT" "-n add: nothing stored"

dav -B"$tmp/kept" set ada-1 -e ada@work.example -s 'NICKNAME:Enchantress'
check_rc 0 "set: succeeds"
check_in "$(cat "$books/Default/ada.vcf")" "ada@work.example" \
    "set -e: an email added"
check_in "$(cat "$books/Default/ada.vcf")" "ada@example.org" \
    "set -e: the old email kept"
check_in "$(cat "$books/Default/ada.vcf")" "NICKNAME:Enchantress" \
    "set -s: replaced"
check_not_in "$(cat "$books/Default/ada.vcf")" "Countess" "set -s: the old one gone"
check_in "$(cat "$books/Default/ada.vcf")" "REV:" "set: REV stamped"
check_in "$(cat "$dav_log")" 'if-match="' "set: updates only that version"
check_in "$(cat "$tmp/kept"/ada-1-*.vcf)" "Countess" \
    "-B: the server's version kept before the change"

dav set alan-1 -d 'EMAIL;TYPE=home'
check_in "$err" "matched nothing" "set -d, nothing matching: warned"
check_in "$(cat "$books/Default/alan.vcf")" "alan@example.org" \
    "set -d, nothing matching: the email kept"

cat > "$tmp/ed-rename" <<'EOF'
#!/bin/sh
awk '{ sub(/^FN:Alan Turing/, "FN:Alan M. Turing"); print }' "$1" \
    > "$1.new" && mv -f -- "$1.new" "$1"
EOF
EDITOR="sh $tmp/ed-rename" dav edit alan-1
check_rc 0 "edit: succeeds"
check_in "$(cat "$books/Default/alan.vcf")" "FN:Alan M. Turing" \
    "edit: the editor's change stored"
EDITOR=true dav edit alan-1
check_in "$err" "unchanged" "edit, nothing changed: said so"
check_not_in "$(verbs)" "PUT" "edit, nothing changed: nothing stored"

cat > "$tmp/ed-race" <<EOF
#!/bin/sh
printf 'X-OTHER:1\r\n' >> "$books/Default/ada.vcf"
awk '{ sub(/^FN:Ada Lovelace/, "FN:Ada King"); print }' "\$1" \
    > "\$1.new" && mv -f -- "\$1.new" "\$1"
EOF
EDITOR="sh $tmp/ed-race" dav edit ada-1
check_rc 1 "edit, changed on the server meanwhile: exit 1"
check_in "$err" "the card changed on the server; your edits are kept in" \
    "edit, a conflict: said so, and the copy named"
kept=$(printf '%s\n' "$err" | sed -n 's/.*kept in //p')
check_in "$(cat "$kept" 2> /dev/null)" "FN:Ada King" \
    "edit, a conflict: the edits kept"
check_in "$(cat "$books/Default/ada.vcf")" "FN:Ada Lovelace" \
    "edit, a conflict: the server's version untouched"

card "$tmp/import.vcf" UID:alan-1 'FN:Alan Turing' 'EMAIL:at@example.org'
card "$tmp/import-new.vcf" UID:kurt-1 'FN:Kurt Godel'
dav import "$tmp/import.vcf" "$tmp/import-new.vcf"
check_rc 0 "import: succeeds"
check_in "$(cat "$books/Default/alan.vcf")" "at@example.org" \
    "import: a known UID updates its card"
check_in "$(cat "$books/Default"/*.vcf)" "UID:kurt-1" \
    "import: a new UID creates"
check_in "$(grep -l UID:kurt-1 "$books/Default"/*.vcf | xargs cat)" \
    "N:Godel;Kurt;;;" "import: a card without N gets one"

dav delete kurt
check_rc 0 "delete: succeeds"
check_not_in "$(cat "$books/Default"/*.vcf)" "UID:kurt-1" "delete: gone"

dav backup -
check_eq "$(printf '%s\n' "$out" | grep -c '^BEGIN:VCARD')" 3 \
    "backup -: every card of the book"
mkdir -p "$tmp/all"
dav -A backup "$tmp/all"
check_rc 0 "backup -A DIR: succeeds"
check_in "$(cat "$tmp/all"/Work-*.vcf)" "UID:grace-1" \
    "backup -A: one file per book"
dav -A backup -
check_rc 2 "backup -A -: exit 2"
dav -A backup "$tmp/nowhere"
check_rc 1 "backup -A, not a directory: exit 1"

# --- credentials -----------------------------------------------------------

printf 'machine 127.0.0.1 login netrc@example.org password fromfile\n' \
    > "$HOME/.netrc"
: > "$dav_log"
run carddav -U "$url" books
check_rc 0 "a netrc entry: succeeds"
check_in "$(cat "$dav_log")" "user=netrc@example.org" \
    "a netrc entry: the login of the URL's host"
export CARDDAV_USER=env@example.org CARDDAV_PASSWORD=envpw
: > "$dav_log"
run carddav -U "$url" books
check_in "$(cat "$dav_log")" "user=env@example.org" \
    "CARDDAV_USER: before the netrc entry"
unset CARDDAV_USER CARDDAV_PASSWORD
rm -f -- "$HOME/.netrc"
run carddav -U "$url" books < /dev/null
check_rc 1 "no user anywhere: exit 1"
check_in "$err" "no user given" "no user anywhere: said so"
printf 'machine mail.example.org login other@example.org password x\n' \
    > "$HOME/.netrc"
: > "$dav_log"
run carddav -U "$url" books < /dev/null
check_rc 1 "an entry for another host only: exit 1"
check_in "$err" "an entry for 127.0.0.1 in" \
    "an entry for another host only: the host looked for named"
check_eq "$(cat "$dav_log")" "" "an entry for another host only: nothing asked"
run carddav books < /dev/null
check_rc 1 "no -U and no user: exit 1"
check_in "$err" "no user given (--user, CARDDAV_USER or EMAIL), and no --url" \
    "no -U and no user: said so, before looking up any server"
rm -f -- "$HOME/.netrc"

# $EMAIL: after CARDDAV_USER and the entry's login, before nothing else.
export EMAIL=mail@example.org CARDDAV_PASSWORD=envpw
: > "$dav_log"
run carddav -U "$url" books
check_rc 0 "EMAIL: succeeds"
check_in "$(cat "$dav_log")" "user=mail@example.org" \
    "EMAIL: the user when nothing else names one"
printf 'machine 127.0.0.1 login netrc@example.org password fromfile\n' \
    > "$HOME/.netrc"
: > "$dav_log"
run carddav -U "$url" books
check_in "$(cat "$dav_log")" "user=netrc@example.org" \
    "EMAIL: after the login of the URL host's entry"
rm -f -- "$HOME/.netrc"
export CARDDAV_USER=env@example.org
: > "$dav_log"
run carddav -U "$url" books
check_in "$(cat "$dav_log")" "user=env@example.org" "EMAIL: after CARDDAV_USER"
unset CARDDAV_USER
export EMAIL=nodomain
run carddav books < /dev/null
check_rc 1 "EMAIL, no -U: the server looked up from it"
check_in "$err" "user has no domain" \
    "EMAIL, no -U: its domain is where the server is looked for"
export EMAIL=
run carddav books < /dev/null
check_in "$err" "no user given" "an empty EMAIL: no user"
unset EMAIL CARDDAV_PASSWORD

# --- refusals --------------------------------------------------------------

for args in '' 'bogus' '--nope list' 'add' 'add -e x@y' 'show' 'import'; do
    # shellcheck disable=SC2086  # each case is a word list
    dav $args
    check_rc 2 "refuses [$args] as a usage error"
    check_not_in "$(verbs)" "PUT" "refuses [$args]: nothing stored"
done
run carddav -h
check_rc 0 "-h: exit 0"
check_in "$out" "Usage: carddav" "-h: the usage"

finish
