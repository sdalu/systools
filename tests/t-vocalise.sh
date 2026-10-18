#!/bin/sh
# vocalise: the Riva request and the WAV assembled from its answers, long
# text split and retried smaller, which engine speaks, the encoders, the
# audio outputs per system, and the refusals.  Every run writes with -o:
# nothing is played.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

mkdir -p "$tmp/home" "$tmp/scratch" "$tmp/voices"
export HOME="$tmp/home" TMPDIR="$tmp/scratch" PIPER_VOICE_PATH="$tmp/voices" \
    VOCALISE_ENGINE=auto VOCALISE_AUDIO=auto OVH_AI_TOKEN='tok.EN-123_x' \
    CURL_ARGV="$tmp/argv" CURL_CONFIG="$tmp/curlrc" CURL_RIVA=100000 \
    CURL_REQUESTS="$tmp/requests" ESPEAK_LOG="$tmp/espeak.log" \
    ESPEAK_LANGS='fr nl' FFMPEG_LOG="$tmp/ffmpeg.log" FAKE_UNAME=FreeBSD
wav=$tmp/out.wav

say() {
    rm -f -- "$wav" "$CURL_ARGV" "$CURL_CONFIG"
    : > "$CURL_REQUESTS"
    : > "$ESPEAK_LOG"
    : > "$FFMPEG_LOG"
    run vocalise "$@"
}
requests() {
    grep -c . "$CURL_REQUESTS"
}
# the sample rate and the data size of the WAV written
rate_of() {
    od -An -tu4 -j 24 -N 4 < "$wav" | tr -d ' '
}
data_of() {
    od -An -tu4 -j 40 -N 4 < "$wav" | tr -d ' '
}

say -o "$wav" 'Hello there.'
check_rc 0 "riva: succeeds"
check_eq "$(requests)" 1 "riva: one request for a short text"
check_in "$(cat "$CURL_REQUESTS")" \
    '{"encoding":1,"language_code":"en-US","sample_rate_hz":22050,"voice_name":"English-US.Female-1","text":"Hello there."}' \
    "riva: English, 22050 Hz, the first voice, the text"
check_in "$(cat "$CURL_ARGV")" "https://nvr-tts-en-us.endpoints.kepler.ai.cloud.ovh.net/api/v1/tts/text_to_audio" \
    "riva: the English model's own host"
check_not_in "$(cat "$CURL_ARGV")" "tok.EN-123_x" "the token is not in curl's arguments"
check_in "$(cat "$CURL_CONFIG")" "Bearer tok.EN-123_x" "the token reaches curl in its config"
check_eq "$(head -c 4 "$wav")" RIFF "a WAV is written"
check_eq "$(rate_of)" 22050 "its header says 22050 Hz"
check_eq "$(data_of)" 12 "its data is the audio the endpoint returned"
check_in "$err" "12 chars in 1 request, free" "announced on stderr"
check_eq "$(ls -A "$TMPDIR")" "" "the temporary directory is removed"

say -r 44100 -o "$wav" 'Hi.'
check_in "$(cat "$CURL_REQUESTS")" '"sample_rate_hz":44100' "-r: asked for at that rate"
check_eq "$(rate_of)" 44100 "-r: and the header written for it, not Riva's 16 kHz"
say -v Male-1 -o "$wav" 'Hi.'
check_in "$(cat "$CURL_REQUESTS")" '"voice_name":"English-US.Male-1"' "-v: the prefix is optional"
say -v Nobody -o "$wav" 'Hi.'
check_rc 1 "-v unknown: exit 1"
check_in "$err" "English-US.Female-Calm" "-v unknown: the voices offered are listed"

say -o "$wav" 'say "hi" \ & <ok>'
check_in "$(cat "$CURL_REQUESTS")" '"text":"say \"hi\" \\ & <ok>"' \
    "quotes and backslashes escaped for JSON"
say -s 0.8 -o "$wav" 'a & b < c'
check_in "$(cat "$CURL_REQUESTS")" \
    '"text":"<speak><prosody rate=\"80%\">a &amp; b &lt; c</prosody></speak>"' \
    "-s: SSML, and the text escaped for it"

long=$(awk 'BEGIN { for (i = 1; i <= 120; i++) printf "Sentence number %03d here. ", i }')
say -o "$wav" "$long"
check_rc 0 "long text: succeeds"
check_eq "$(requests)" 3 "long text: split into pieces under the limit"
check_in "$err" "in 3 requests" "long text: the requests counted"
check_eq "$(awk '{ t = $0; sub(/.*"text":"/, "", t); sub(/"}$/, "", t); if (length(t) > 1200) bad = 1 } END { print bad + 0 }' "$CURL_REQUESTS")" 0 \
    "no piece is over 1200 characters"
check_eq "$(awk '{ t = $0; sub(/.*"text":"/, "", t); sub(/"}$/, "", t); if (t !~ /here\.$/) bad = 1 } END { print bad + 0 }' "$CURL_REQUESTS")" 0 \
    "every piece ends on a sentence"
check_eq "$(data_of)" "$(awk '{ t = $0; sub(/.*"text":"/, "", t); sub(/"}$/, "", t); n += length(t) } END { print n }' "$CURL_REQUESTS")" \
    "the pieces' audio is joined in one WAV"
export CURL_RIVA=400
say -o "$wav" "$long"
check_rc 0 "too long for the model: still succeeds"
check_in "$err" "retrying at 595 chars" "too long: retried at half the first cut (1190)"
check_in "$err" "retrying at 297 chars" "still too long: halved again"
export CURL_RIVA=10
say -o "$wav" "$long"
check_rc 1 "never short enough: exit 1"
check_in "$err" "still too big for the model" "never short enough: said so"
export CURL_RIVA=100000

unset CURL_RIVA
export CURL_CODE=500 CURL_BODY='boom'
say -o "$wav" 'Hi.'
check_rc 1 "HTTP 500: exit 1"
check_in "$err" "HTTP 500 from the synthesis endpoint" "HTTP 500: said so"
export CURL_CODE=200 CURL_BODY='not a wav at all, though long enough'
say -o "$wav" 'Hi.'
check_rc 1 "an answer that is not a WAV: exit 1"
check_in "$err" "something other than the" "an answer that is not a WAV: said so"
unset CURL_CODE CURL_BODY
export CURL_RIVA=100000

# shellcheck disable=SC2089,SC2090  # the quote is the point
export OVH_AI_TOKEN='bad"token'
say -o "$wav" 'Hi.'
check_rc 1 "a token with a quote: exit 1"
check_eq "$(requests)" 0 "a token with a quote: nothing sent"
unset OVH_AI_TOKEN
say -o "$wav" 'Hi.'
check_rc 1 "no token: exit 1"
check_in "$err" "no API token" "no token: said so"
# shellcheck disable=SC2090
export OVH_AI_TOKEN='tok.EN-123_x'

say -l fr -o "$wav" 'Bonjour.'
check_rc 0 "French: succeeds"
check_eq "$(requests)" 0 "French: Riva has no French voice, nothing sent"
check_in "$(cat "$ESPEAK_LOG")" "-v fr -w " "French: espeak-ng speaks it"
check_in "$err" "(espeak-ng, fr)" "French: announced as espeak-ng"
say -E local -o "$wav" 'Hello.'
check_rc 1 "-E local, English, no local engine knows it: exit 1"
check_eq "$(requests)" 0 "-E local: the text never leaves the machine"
say -E offline -o "$wav" 'Hello.'
check_eq "$(requests)" 1 "-E offline: falls back to the network"
say -E riva -l fr -o "$wav" 'Bonjour.'
check_rc 1 "-E riva -l fr: exit 1"
say -l xx -o "$wav" 'Hm.'
check_rc 1 "a language no engine knows: exit 1"
say -l fr -s 1.5 -o "$wav" 'Vite.'
check_in "$(cat "$ESPEAK_LOG")" "-s 262" "espeak -s: words per minute scaled from 175"

say -o "$tmp/out.mp3" 'Hi.'
check_in "$(cat "$FFMPEG_LOG")" "-c:a libmp3lame" "-o .mp3: encoded by ffmpeg with lame"
check_eq "$(head -c 7 "$tmp/out.mp3")" "FFMPEG:" "-o .mp3: ffmpeg's output written"
say -f flac -b 5 -o "$tmp/out.flac" 'Hi.'
check_in "$(cat "$FFMPEG_LOG")" "-compression_level 5" "-f flac -b 5: the compression level"
say -o "$tmp/OUT.WAV" 'Hi.'
check_eq "$(cat "$FFMPEG_LOG")" "" "-o .WAV: a copy, no encoder"

run vocalise -h
check_in "$out" "auto tries, in order, sndio oss" "FreeBSD: sndio, then oss"
export FAKE_UNAME=Linux
run vocalise -h
check_in "$out" "auto tries, in order, pulse alsa" "Linux: pulse, then alsa"
export FAKE_UNAME=FreeBSD

say -o "$wav" '   '
check_rc 1 "whitespace only: exit 1"
check_in "$err" "no text to speak" "whitespace only: said so"
printf 'From stdin.\n' > "$tmp/text"
rm -f -- "$wav"
: > "$CURL_REQUESTS"
# shellcheck disable=SC2086  # SH may carry options
$SH "$top/bin/vocalise" -q -o "$wav" < "$tmp/text"
check_in "$(cat "$CURL_REQUESTS")" '"text":"From stdin."' "text from stdin, its newline dropped"

for args in '-A bogus' '-E bogus' '-r 7000' '-r abc' '-b x' '-f flac -b 9' \
    '-s 3' '-s abc' '-z'; do
    # shellcheck disable=SC2086  # each case is a word list
    say $args -o "$wav" 'Hi.'
    check_rc 2 "refuses [$args] as a usage error"
    check_eq "$(requests)" 0 "refuses [$args]: nothing sent"
done

finish
