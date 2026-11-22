#!/bin/bash
set -uo pipefail

for pkg in curl unzip xz-utils fontconfig; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
        echo "$pkg not found. Installing..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
    fi
done

failed_count=0

font_is_installed() {
    local search_name="$1"
    local target_dir="$2"
    if [[ -d "$target_dir" ]] && find "$target_dir" -type f \( -iname "*.ttf" -o -iname "*.otf" \) | grep -q .; then
        return 0
    fi
    if fc-list : family | grep -iqF "$search_name"; then
        return 0
    fi
    return 1
}

# 1. Standard Repository Fonts
echo "Checking curated system font packages..."
apt_fonts=(
    fonts-crosextra-carlito
    fonts-crosextra-caladea
    fonts-inter
    fonts-jetbrains-mono
    fonts-noto-color-emoji
    fonts-roboto
    fonts-open-sans
    fonts-lato
    fonts-montserrat
    fonts-quicksand
    fonts-dancingscript
)
missing_apt_fonts=()

for pkg in "${apt_fonts[@]}"; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        echo "⏭️  $pkg already installed. Skipping."
    else
        missing_apt_fonts+=("$pkg")
    fi
done

if [[ ${#missing_apt_fonts[@]} -gt 0 ]]; then
    echo "Installing missing system font packages: ${missing_apt_fonts[*]}..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing_apt_fonts[@]}"; then
        echo "⚠️  One or more APT font packages failed to install."
        ((failed_count++))
    fi
fi

# 2. Nerd Fonts
echo "Checking Nerd Fonts..."
nerd_fonts=("Meslo" "Hack" "FiraCode" "JetBrainsMono")
for font in "${nerd_fonts[@]}"; do
    dir="/usr/share/fonts/nerdfonts/${font,,}"
    if font_is_installed "$font Nerd Font" "$dir" || font_is_installed "$font" "$dir"; then
        echo "⏭️  Nerd Font '$font' already installed. Skipping."
        continue
    fi

    printf -v url_tar 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/%s.tar.xz' "$font"
    printf -v url_zip 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/%s.zip' "$font"

    echo "Installing Nerd Font: $font..."
    sudo mkdir -p "$dir"
    if sudo curl -fsSL "$url_tar" -o "$dir/$font.tar.xz" && sudo tar -xJf "$dir/$font.tar.xz" -C "$dir" 2>/dev/null; then
        sudo find "$dir" -type f ! \( -iname "*.ttf" -o -iname "*.otf" \) -delete
        echo "✅ Installed Nerd Font: $font"
        declare -F record_op >/dev/null && record_op "PASS" "Nerd Font" "$font"
    elif sudo curl -fsSL "$url_zip" -o "$dir/$font.zip" && sudo unzip -tq "$dir/$font.zip" >/dev/null 2>&1; then
        sudo unzip -o "$dir/$font.zip" -d "$dir" >/dev/null
        sudo find "$dir" -type f ! \( -iname "*.ttf" -o -iname "*.otf" \) -delete
        echo "✅ Installed Nerd Font: $font"
        declare -F record_op >/dev/null && record_op "PASS" "Nerd Font" "$font"
    else
        echo "⚠️  Failed to download Nerd Font '$font'."
        declare -F record_op >/dev/null && record_op "FAIL" "Nerd Font" "$font"
        sudo rmdir "$dir" 2>/dev/null || true
        ((failed_count++))
    fi
    sudo rm -f "$dir/$font.tar.xz" "$dir/$font.zip"
done

# 3. Additional Google Fonts via Fontsource CDN
echo "Checking extra Google Fonts..."
extra_google_fonts=(
    "Bebas Neue:bebas-neue:400"
    "Anton:anton:400"
    "Poppins:poppins:400,500,600,700"
    "Playfair Display:playfair-display:400,700"
    "Merriweather:merriweather:400,700"
    "Roboto Mono:roboto-mono:400,700"
    "Raleway:raleway:400,600,700"
    "Nunito:nunito:400,600,700"
    "Fira Sans:fira-sans:400,600,700"
    "Work Sans:work-sans:400,600,700"
    "PT Sans:pt-sans:400,700"
    "Source Sans 3:source-sans-3:400,600,700"
    "Cinzel:cinzel:400,700"
    "Pacifico:pacifico:400"
    "Permanent Marker:permanent-marker:400"
    "Archivo Black:archivo-black:400"
    "Barlow Condensed:barlow-condensed:400,600,700"
    "Titillium Web:titillium-web:400,600,700"
    "Oswald:oswald:400,600,700"
    "Lora:lora:400,700"
    "Libre Baskerville:libre-baskerville:400,700"
    "Caveat:caveat:400,700"
)

for entry in "${extra_google_fonts[@]}"; do
    IFS=':' read -r font slug weights <<< "$entry"
    dir="/usr/share/fonts/google/$slug"

    if font_is_installed "$font" "$dir"; then
        echo "⏭️  Google Font '$font' already installed. Skipping."
        continue
    fi

    echo "Installing Google Font: $font..."
    sudo mkdir -p "$dir"
    downloaded=0

    IFS=',' read -ra weight_arr <<< "$weights"
    for w in "${weight_arr[@]}"; do
        printf -v ttf_url 'https://cdn.jsdelivr.net/fontsource/fonts/%s@latest/latin-%s-normal.ttf' "$slug" "$w"
        printf -v out_file '%s/%s-%s.ttf' "$dir" "$slug" "$w"
        if sudo curl -fsSL "$ttf_url" -o "$out_file" && [[ -s "$out_file" ]]; then
            ((downloaded++))
        else
            sudo rm -f "$out_file"
        fi
    done

    if [[ $downloaded -gt 0 ]]; then
        echo "✅ Installed Google Font: $font ($downloaded weight(s))"
        declare -F record_op >/dev/null && record_op "PASS" "Google Font" "$font"
    else
        echo "⚠️  Failed to download Google Font '$font'."
        declare -F record_op >/dev/null && record_op "FAIL" "Google Font" "$font"
        sudo rmdir "$dir" 2>/dev/null || true
        ((failed_count++))
    fi
done

# 4. DaFont Fonts
echo "Checking DaFont Fonts..."
dafonts=("photonica")
for font in "${dafonts[@]}"; do
    dir="/usr/share/fonts/dafont/$font"
    if font_is_installed "$font" "$dir"; then
        echo "⏭️  DaFont '$font' already installed. Skipping."
        continue
    fi

    printf -v url 'https://dl.dafont.com/dl/?f=%s' "$font"
    page_url="https://www.dafont.com/${font}.font"
    echo "Installing DaFont: $font..."
    sudo mkdir -p "$dir"
    tmp_zip=$(mktemp --suffix=.zip)

    # DaFont may reject command-line downloads without browser headers/referrer.
    # Download as the current user, then validate before extracting with sudo.
    if curl --fail --location --silent --show-error --retry 3 --retry-delay 2 \
        --user-agent 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36' \
        --referer "$page_url" "$url" -o "$tmp_zip" \
        && unzip -tq "$tmp_zip" >/dev/null 2>&1; then
        if sudo unzip -oq "$tmp_zip" -d "$dir" >/dev/null; then
            sudo find "$dir" -type f ! \( -iname "*.ttf" -o -iname "*.otf" \) -delete
            if sudo find "$dir" -type f \( -iname "*.ttf" -o -iname "*.otf" \) -print -quit | grep -q .; then
                echo "✅ Installed DaFont: $font"
                declare -F record_op >/dev/null && record_op "PASS" "DaFont" "$font"
            else
                echo "⚠️  Archive extracted, but no font files found for '$font'."
                declare -F record_op >/dev/null && record_op "FAIL" "DaFont" "$font (no font files)"
                sudo rm -rf "$dir"
                ((failed_count++))
            fi
        else
            echo "⚠️  Failed to extract DaFont '$font'."
            declare -F record_op >/dev/null && record_op "FAIL" "DaFont" "$font (extract failed)"
            sudo rm -rf "$dir"
            ((failed_count++))
        fi
    else
        echo "⚠️  DaFont download failed or response was not a valid ZIP for '$font'."
        declare -F record_op >/dev/null && record_op "FAIL" "DaFont" "$font (download/ZIP validation failed)"
        sudo rm -rf "$dir"
        ((failed_count++))
    fi
    rm -f "$tmp_zip"
done

echo "Refreshing font cache..."
sudo fc-cache -fv >/dev/null 2>&1 || true

if (( failed_count > 0 )); then
    echo "⚠️  Font installation finished with $failed_count error(s)."
    exit 1
fi

echo "✅ All fonts installed and font cache refreshed!"
exit 0
