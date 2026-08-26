#!/usr/bin/env bash

set -Eeuo pipefail
umask 022

readonly MOBILE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly MASTER_SOURCE="${MOBILE_ROOT}/assets/branding/ts-phone-logo-source.png"
readonly ICON_SOURCE="${MOBILE_ROOT}/assets/branding/ts-phone-icon.png"
readonly MARK_SOURCE="${MOBILE_ROOT}/assets/branding/ts-phone-mark.png"
readonly MONOCHROME_SOURCE="${MOBILE_ROOT}/assets/branding/ts-phone-mark-monochrome.png"

command -v magick >/dev/null 2>&1 || {
    printf 'Error[ts-phone-icons]: ImageMagick magick is required\n' >&2
    exit 1
}
[[ -f "$MASTER_SOURCE" && ! -L "$MASTER_SOURCE" ]] || {
    printf 'Error[ts-phone-icons]: source PNG is missing or unsafe: %s\n' "$MASTER_SOURCE" >&2
    exit 1
}

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/ts-phone-icons.XXXXXX")
cleanup() {
    if [[ -d "$temporary_dir" && "$temporary_dir" == "${TMPDIR:-/tmp}"/ts-phone-icons.* ]]; then
        rm -rf -- "$temporary_dir"
    fi
}
trap cleanup EXIT

create_monochrome_mark() {
    local color_source=$1
    local destination=$2
    local alpha_mask="${temporary_dir}/$(basename -- "$destination").alpha.png"

    magick "$color_source" -alpha extract -strip "$alpha_mask"
    magick -size 1024x1024 canvas:white "$alpha_mask" \
        -alpha off \
        -compose CopyOpacity \
        -composite \
        -strip \
        "PNG32:${destination}"
}

create_brand_sources() {
    local cropped="${temporary_dir}/cropped.png"
    local extracted="${temporary_dir}/extracted.png"
    local adaptive_mark="${temporary_dir}/adaptive-mark.png"

    # Remove the baked rounded tile and keep only the supplied TSPi character.
    magick "$MASTER_SOURCE" \
        -crop 1034x1034+110+110 +repage \
        -alpha on \
        -fuzz 18% \
        -transparent white \
        -trim +repage \
        "$cropped"
    magick "$cropped" \
        -channel A \
        -morphology Erode Diamond:1 \
        -blur 0x0.35 \
        +channel \
        -strip \
        "PNG32:${extracted}"

    magick "$extracted" \
        -filter Lanczos \
        -resize 900x900 \
        -gravity center \
        -background none \
        -extent 1024x1024 \
        -strip \
        "PNG32:${MARK_SOURCE}"
    create_monochrome_mark "$MARK_SOURCE" "$MONOCHROME_SOURCE"

    magick "$extracted" \
        -filter Lanczos \
        -resize 760x760 \
        -gravity center \
        -background white \
        -extent 1024x1024 \
        -alpha remove -alpha off \
        -strip \
        "PNG24:${ICON_SOURCE}"

    magick "$extracted" \
        -filter Lanczos \
        -resize 700x700 \
        -gravity center \
        -background none \
        -extent 1024x1024 \
        -strip \
        "PNG32:${adaptive_mark}"
    create_monochrome_mark "$adaptive_mark" "${temporary_dir}/adaptive-mark-monochrome.png"
}

render_opaque_icon() {
    local relative_target=$1
    local size=$2
    local destination="${MOBILE_ROOT}/${relative_target}"
    local temporary_icon="${temporary_dir}/$(basename -- "$destination")-${size}.png"

    magick -background none "$ICON_SOURCE" \
        -filter Lanczos \
        -resize "${size}x${size}!" \
        -strip \
        "PNG24:${temporary_icon}"

    local geometry
    geometry=$(magick identify -format '%wx%h:%[opaque]' "$temporary_icon")
    [[ "$geometry" == "${size}x${size}:True" ]] || {
        printf 'Error[ts-phone-icons]: invalid output %s (%s)\n' "$relative_target" "$geometry" >&2
        exit 1
    }
    install -m 0644 "$temporary_icon" "$destination"
}

render_transparent_icon() {
    local source_file=$1
    local relative_target=$2
    local size=$3
    local destination="${MOBILE_ROOT}/${relative_target}"
    local temporary_icon="${temporary_dir}/$(basename -- "$destination")-${size}.png"

    magick -background none "$source_file" \
        -filter Lanczos \
        -resize "${size}x${size}!" \
        -strip \
        "PNG32:${temporary_icon}"

    local geometry
    geometry=$(magick identify -format '%wx%h:%[opaque]' "$temporary_icon")
    [[ "$geometry" == "${size}x${size}:False" ]] || {
        printf 'Error[ts-phone-icons]: invalid adaptive output %s (%s)\n' "$relative_target" "$geometry" >&2
        exit 1
    }
    install -d -m 0755 "$(dirname -- "$destination")"
    install -m 0644 "$temporary_icon" "$destination"
}

create_brand_sources

render_opaque_icon "android/app/src/main/res/mipmap-mdpi/ic_launcher.png" 48
render_opaque_icon "android/app/src/main/res/mipmap-hdpi/ic_launcher.png" 72
render_opaque_icon "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png" 96
render_opaque_icon "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png" 144
render_opaque_icon "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" 192

declare -A android_adaptive_sizes=(
    [mdpi]=108
    [hdpi]=162
    [xhdpi]=216
    [xxhdpi]=324
    [xxxhdpi]=432
)

for density in "${!android_adaptive_sizes[@]}"; do
    adaptive_size="${android_adaptive_sizes[$density]}"
    render_transparent_icon \
        "${temporary_dir}/adaptive-mark.png" \
        "android/app/src/main/res/drawable-${density}/ic_launcher_foreground.png" \
        "$adaptive_size"
    render_transparent_icon \
        "${temporary_dir}/adaptive-mark-monochrome.png" \
        "android/app/src/main/res/drawable-${density}/ic_launcher_monochrome.png" \
        "$adaptive_size"
done

declare -A ios_sizes=(
    [Icon-App-20x20@1x.png]=20
    [Icon-App-20x20@2x.png]=40
    [Icon-App-20x20@3x.png]=60
    [Icon-App-29x29@1x.png]=29
    [Icon-App-29x29@2x.png]=58
    [Icon-App-29x29@3x.png]=87
    [Icon-App-40x40@1x.png]=40
    [Icon-App-40x40@2x.png]=80
    [Icon-App-40x40@3x.png]=120
    [Icon-App-60x60@2x.png]=120
    [Icon-App-60x60@3x.png]=180
    [Icon-App-76x76@1x.png]=76
    [Icon-App-76x76@2x.png]=152
    [Icon-App-83.5x83.5@2x.png]=167
    [Icon-App-1024x1024@1x.png]=1024
)

for filename in "${!ios_sizes[@]}"; do
    render_opaque_icon \
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/${filename}" \
        "${ios_sizes[$filename]}"
done

printf 'Info[ts-phone-icons]: generated legacy, adaptive, monochrome, and iOS icons\n'
