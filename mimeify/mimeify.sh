#!/bin/bash

# Directory containing the files
DIR=$(pwd)

# Change to the specified directory
cd "$DIR" || exit

# Iterate over each file in the directory
for FILE in *; do
    if [ -f "$FILE" ]; then
        # Get the MIME type of the file
        MIME_TYPE=$(file --mime-type -b "$FILE")
        
        # Determine the correct extension based on MIME type
        case $MIME_TYPE in
            image/jpeg)
                EXT="jpg"
                ;;
            image/png)
                EXT="png"
                ;;
            image/gif)
                EXT="gif"
                ;;
            video/mp4)
                EXT="mp4"
                ;;
            video/x-matroska)
                EXT="mkv"
                ;;
            video/quicktime)
                EXT="mov"
                ;;
            video/x-msvideo)
                EXT="avi"
                ;;
            video/x-flv)
                EXT="flv"
                ;;
	    video/x-m4v)
		EXT="m4v"
		;;
            *)
                echo "Unknown MIME type: $MIME_TYPE for file: $FILE"
                continue
                ;;
        esac

        # Rename the file with the correct extension
        mv "$FILE" "$FILE.$EXT"
    fi
done
