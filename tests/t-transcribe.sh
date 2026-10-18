#!/bin/sh
# transcribe: the request each option makes, where the token goes and
# where it is looked for, the cost line, -o's never-clobber, and the
# refusals.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

mkdir -p "$tmp/home" "$tmp/scratch"
export HOME="$tmp/home" TMPDIR="$tmp/scratch" CURL_ARGV="$tmp/argv" \
    CURL_CONFIG="$tmp/curlrc" FFMPEG_LOG="$tmp/ffmpeg.log" \
    OVH_AI_TOKEN='tok.EN-123_x' CURL_BODY='hello world'
printf 'RIFF....' > "$tmp/clip.wav"
clip=$tmp/clip.wav

tr_() {
    rm -f -- "$CURL_ARGV" "$CURL_CONFIG"
    : > "$FFMPEG_LOG"
    run transcribe "$@"
}
argv() {
    cat -- "$CURL_ARGV" 2> /dev/null
}

tr_ -q "$clip"
check_rc 0 "succeeds"
check_eq "$out" "hello world" "the transcript on stdout"
check_eq "$(wc -c < "$tmp/out" | tr -d ' ')" 12 "a newline the API left out is added"
check_in "$(argv)" "https://oai.endpoints.kepler.ai.cloud.ovh.net/v1/audio/transcriptions" \
    "posted to AI Endpoints' transcription route"
check_in "$(argv)" "--form-string
model=whisper-large-v3
--form-string
response_format=text" "whisper-large-v3 and text by default, as plain fields"
check_in "$(argv)" "-F
file=@$tmp/scratch/" "the audio is the one file upload"
check_in "$(argv)" "/audio1.flac" "resampled by ffmpeg to FLAC first"
check_in "$(cat "$FFMPEG_LOG")" "-ar 16000 -ac 1" "ffmpeg: 16 kHz mono"
check_not_in "$(argv)" "tok.EN-123_x" "the token is not in curl's arguments"
check_eq "$(cat "$CURL_CONFIG")" 'header = "Authorization: Bearer tok.EN-123_x"' \
    "the token reaches curl in its config file"
check_eq "$(ls -A "$TMPDIR")" "" "the temporary directory is removed"

tr_ -q -t -l fr -p '@/etc/passwd names Alice' "$clip"
check_in "$(argv)" "model=whisper-large-v3-turbo" "-t: the turbo model"
check_in "$(argv)" "--form-string
language=fr" "-l: the language"
check_in "$(argv)" "--form-string
prompt=@/etc/passwd names Alice" "-p: a plain field, never read as a file"
tr_ -q -d -w "$clip"
check_in "$(argv)" "response_format=verbose_json" "-d -w: verbose_json"
check_in "$(argv)" "diarize=true" "-d: diarize"
check_in "$(argv)" "timestamp_granularities[]=word" "-w: word timestamps"
tr_ -q -n "$clip"
check_eq "$(cat "$FFMPEG_LOG")" "" "-n: no ffmpeg"
check_in "$(argv)" "/audio1.wav" "-n: uploaded as it is, its extension kept"
cp "$clip" "$tmp/clip.wav,v"
tr_ -q -n "$tmp/clip.wav,v"
check_in "$(argv)" "/audio1.wav" "an extension is cut at what -F would misread (wav,v is wav)"
check_not_in "$(argv)" ",v" "the comma never reaches -F"

export FFPROBE_DURATION=90
tr_ "$clip"
check_in "$err" "clip.wav - 1:30 audio, ~0.0037 EUR (whisper-large-v3)" \
    "the duration and cost on stderr"
tr_ -t "$clip"
check_in "$err" "1:30 audio, ~0.0012 EUR (whisper-large-v3-turbo)" "-t: the turbo rate"
export FFPROBE_DURATION=0.94
tr_ "$clip"
check_in "$err" "0.94 s audio" "under a second: not 0:00"
unset FFPROBE_DURATION
tr_ -q "$clip"
check_eq "$err" "" "-q: nothing on stderr"

printf 'previous\n' > "$tmp/out.txt"
tr_ -q -o "$tmp/out.txt" "$clip"
check_eq "$(cat "$tmp/out.txt")" "hello world" "-o: the transcript written"
printf 'previous\n' > "$tmp/out.txt"
# shellcheck disable=SC2089,SC2090  # the quotes are the JSON body's
CURL_BODY='{"error":"boom"}'
# shellcheck disable=SC2090
export CURL_CODE=500 CURL_BODY
tr_ -q -o "$tmp/out.txt" "$clip"
check_rc 1 "HTTP 500: exit 1"
check_in "$err" "HTTP 500" "HTTP 500: said so, with the body"
check_eq "$(cat "$tmp/out.txt")" "previous" "HTTP 500: -o's file left as it was"
CURL_BODY='hello world'
# shellcheck disable=SC2090
export CURL_CODE=200 CURL_BODY CURL_EXIT=7
tr_ -q "$clip"
check_rc 1 "curl fails: exit 1"
unset CURL_EXIT

unset OVH_AI_TOKEN
tr_ -q "$clip"
check_rc 1 "no token anywhere: exit 1"
check_in "$err" "no API token" "no token anywhere: said so"
printf 'machine oai.endpoints.kepler.ai.cloud.ovh.net login x password from.authinfo\n' \
    > "$HOME/.authinfo"
tr_ -q "$clip"
check_in "$(cat "$CURL_CONFIG")" "Bearer from.authinfo" "the token from ~/.authinfo"
mkdir -p "$HOME/.config/ovhcloud"
printf 'from.file\n' > "$HOME/.config/ovhcloud/ai-token"
tr_ -q "$clip"
check_in "$(cat "$CURL_CONFIG")" "Bearer from.file" "the token file before ~/.authinfo"
export OVH_AI_ENDPOINTS_API_KEY='from.env'
tr_ -q "$clip"
check_in "$(cat "$CURL_CONFIG")" "Bearer from.env" "the environment before the file"
# shellcheck disable=SC2089,SC2090  # the quote is the point
export OVH_AI_ENDPOINTS_API_KEY='bad"token'
tr_ -q "$clip"
check_rc 1 "a token with a quote: exit 1"
check_in "$err" "no bearer token has" "a token with a quote: refused"
check_eq "$(argv)" "" "a token with a quote: curl not run"
export OVH_AI_TOKEN='tok.EN-123_x'
unset OVH_AI_ENDPOINTS_API_KEY

# The 900-character limit counts characters under any locale: 500
# accented ones are 1000 bytes, and under C wc -m would count bytes.
accented=$(awk 'BEGIN { while (n++ < 500) printf "\303\251" }')
export LC_ALL=C
tr_ -p "$accented" "$clip"
unset LC_ALL
check_rc 0 "C locale, 500 accented characters: under the limit"
check_in "$err" "prompt set (500 chars)" "C locale: characters counted, not bytes"

long=$(awk 'BEGIN { while (n++ < 901) printf "a" }')
for args in "-f srtx $clip" "-o $tmp/o $clip $clip" "-p $long $clip" '' \
    "-z $clip"; do
    # shellcheck disable=SC2086  # each case is a word list
    tr_ -q $args
    check_rc 2 "refuses [${args%% *}] as a usage error"
    check_eq "$(argv)" "" "refuses [${args%% *}]: curl not run"
done
run transcribe -M
check_eq "$out" "whisper-large-v3" "-M: the model these flags select"
run transcribe -h
check_rc 0 "-h: help"

finish
