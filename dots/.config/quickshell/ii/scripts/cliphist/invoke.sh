#!/usr/bin/env bash
# Usage: invoke.sh <cliphist list line> <cliphist binary> <web search base url>
# Opens URLs / existing paths / images with the default app, otherwise web-searches the text.
entry="$1"; bin="${2:-cliphist}"; engine="${3:-https://www.google.com/search?q=}"
dir=/tmp/quickshell/media/cliphist-invoke
mkdir -p "$dir"

if [[ "$entry" =~ ^[0-9]+$'\t'\[\[\ binary\ data ]]; then
    ext=$(grep -oiE '\b(png|jpe?g|gif|webp|bmp|svg)\b' <<< "$entry" | head -1)
    f="$dir/image.${ext:-png}"
    printf '%s\n' "$entry" | "$bin" decode > "$f" && exec xdg-open "$f"
    exit 1
fi

t=$(printf '%s\n' "$entry" | "$bin" decode | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
[[ -z "$t" ]] && exit 1
p="${t/#\~/$HOME}"

if [[ "$t" =~ ^(https?|ftp|file|mailto): ]]; then
    exec xdg-open "$t"
elif [[ "$t" =~ ^www\. ]]; then
    exec xdg-open "https://$t"
elif [[ "$t" != *$'\n'* && -e "$p" ]]; then
    exec xdg-open "$p"
else
    exec xdg-open "${engine}$(jq -rn --arg q "$t" '$q|@uri')"
fi
