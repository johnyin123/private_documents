#!/usr/bin/env bash
# This script converts the selected file to PDF using LibreOffice
# For general instructions on how to use Nautilus scripts, see
# https://help.ubuntu.com/community/NautilusScriptsHowto
#
# Save this script in ~/.local/share/nautilus/scripts/ and make it
# executable.

IFS_BAK=$IFS
IFS="
"

for SelectedFile in ${NAUTILUS_SCRIPT_SELECTED_FILE_PATHS}; do
    # libreoffice7.1
    soffice \
        --nodefault \
        --nolockcheck \
        --nologo \
        --norestore \
        --nofirststartwizard \
        --convert-to pdf "${SelectedFile}"
done

IFS=$IFS_BAK
