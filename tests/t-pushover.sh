#!/bin/sh
# pushover: what reaches curl and how, the placeholders, the API's
# answers, and the refusals.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export PUSHOVER_CONFIG="$tmp/pushover.yml" CURL_ARGV="$tmp/argv" \
    CURL_STDIN="$tmp/stdin" FAKE_NODENAME=box.example.org
cat > "$PUSHOVER_CONFIG" <<'EOF'
# a comment
app:
  sauron:    aaaa1111AAAA
  conscious: "bbbb2222BBBB"   # quoted, with a comment
user:
  alice:     uuuu3333UUUU
  bob:       'vvvv4444VVVV'
EOF

send() {
    rm -f -- "$CURL_ARGV" "$CURL_STDIN"
    run pushover "$@"
}
argv() {
    cat -- "$CURL_ARGV" 2> /dev/null
}

send sauron 'hello'
check_rc 0 "sends with the default user"
check_in "$(cat "$CURL_STDIN")" 'data-urlencode = "token=aaaa1111AAAA"' \
    "the app token goes to curl on stdin"
check_in "$(cat "$CURL_STDIN")" 'data-urlencode = "user=uuuu3333UUUU"' \
    "the first user is the default"
check_not_in "$(argv)" "aaaa1111AAAA" "the app token is not in curl's arguments"
check_not_in "$(argv)" "uuuu3333UUUU" "the user key is not in curl's arguments"

send sauron '@/etc/passwd'
check_in "$(argv)" "--data-urlencode
message=@/etc/passwd" "a message starting with @ is sent as text"
check_not_in "$(argv)" "-F" "no -F form, which reads @file"

send sauron 'on %{HOST} / %{HOSTNAME}, %{NOPE}.'
check_in "$(argv)" "message=on box / box.example.org, ." \
    "placeholders: short and full host name, unknown ones removed"

# shellcheck disable=SC2016  # a literal $HOME is the point
send sauron 'a\nb\\c $HOME'
# shellcheck disable=SC2016
check_in "$(argv)" 'message=a\nb\\c $HOME' "backslashes and dollars arrive as typed"

send -t 'a "title"' bob:conscious 'm'
check_in "$(cat "$CURL_STDIN")" '"token=bbbb2222BBBB"' "USER:APP: the app, quotes and comment stripped"
check_in "$(cat "$CURL_STDIN")" '"user=vvvv4444VVVV"' "USER:APP: the user, single quotes stripped"
check_in "$(argv)" 'title=a "title"' "the title is sent"

send -v sauron 'm'
check_in "$err" "sent (request req-1)" "-v reports the request id"

export CURL_CODE=429
send sauron 'm'
check_rc 1 "429: exit 1"
check_in "$err" "message limit reached" "429: said so"
export CURL_CODE=400 \
    CURL_BODY='{"user":"invalid","errors":["user identifier is invalid"],"status":0}'
send sauron 'm'
check_rc 1 "400: exit 1"
check_in "$err" '"user identifier is invalid"' "400: the API's error is shown"
unset CURL_CODE CURL_BODY
export CURL_EXIT=7
send sauron 'm'
check_rc 1 "curl fails: exit 1"
check_in "$err" "request failed" "curl fails: said so"
unset CURL_EXIT

send nosuch 'm'
check_rc 1 "unknown app: exit 1"
check_eq "$(argv)" "" "unknown app: curl is not called"
send carol:sauron 'm'
check_rc 1 "unknown user: exit 1"
check_in "$err" "unknown user: carol" "unknown user: named"

printf 'app:\n  evil: abc"def\nuser:\n  me: x\n' > "$tmp/bad.yml"
export PUSHOVER_CONFIG="$tmp/bad.yml"
send evil 'm'
check_rc 1 "a token with a quote: exit 1"
check_in "$err" "malformed token" "a token with a quote: refused"
check_eq "$(argv)" "" "a token with a quote: never reaches curl's config"

export PUSHOVER_CONFIG="$tmp/none"
send sauron 'm'
check_rc 1 "no configuration: exit 1"
check_in "$err" "not found" "no configuration: said so"
export PUSHOVER_CONFIG="$tmp/pushover.yml"

send sauron ''
check_rc 1 "empty message: exit 1"
for args in 'sauron' '' 'a b c' '-z sauron m'; do
    # shellcheck disable=SC2086  # each case is a word list
    send $args
    check_rc 2 "refuses [$args] as a usage error"
done

finish
