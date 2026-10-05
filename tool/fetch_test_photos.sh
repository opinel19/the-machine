#!/bin/sh
# Downloads the photos the integration tests run on and writes them into
# integration_test/test_faces.dart (or the path given). The photos are not
# kept in the repository. macOS: needs curl, sips and base64.
#
#     tool/fetch_test_photos.sh && flutter test integration_test -d <device>
set -eu
cd "$(dirname "$0")/.."
out=${1:-integration_test/test_faces.dart}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

faces=https://raw.githubusercontent.com/ageitgey/face_recognition/master
commons=https://upload.wikimedia.org/wikipedia/commons/thumb

# Adds one photo as a base64 constant: name, longest side (0 keeps the size), URL.
photo() {
  curl -sfL -A 'the-machine-tests/1.0 (integration test photos)' -o "$tmp/$1.jpg" "$3"
  if [ "$2" -gt 0 ]; then
    sips -Z "$2" -s formatOptions 80 "$tmp/$1.jpg" --out "$tmp/$1.jpg" >/dev/null
  fi
  printf "const %s =\n    '%s';\n" "$1" "$(base64 -i "$tmp/$1.jpg" | tr -d '\n')" >>"$tmp/out.dart"
}

cat >"$tmp/out.dart" <<'EOF'
// Test photos, written by tool/fetch_test_photos.sh. Not in the repository.
// Faces: US government portraits (public domain), from the face_recognition
// examples, downscaled.
EOF
photo obamaJpeg 480 "$faces/examples/obama.jpg"
photo obama2Jpeg 480 "$faces/examples/obama2.jpg"
photo obama3Jpeg 480 "$faces/tests/test_images/obama3.jpg"
photo bidenJpeg 480 "$faces/examples/biden.jpg"
cat >>"$tmp/out.dart" <<'EOF'

// Porsche 911 in Berlin, Wikimedia Commons, CC BY-SA 4.0:
// https://commons.wikimedia.org/wiki/File:Porsche_911,_70_Years_Porsche_Sports_Car,_Berlin_(1X7A3904).jpg
EOF
photo carJpeg 0 "$commons/5/52/Porsche_911%2C_70_Years_Porsche_Sports_Car%2C_Berlin_%281X7A3904%29.jpg/500px-Porsche_911%2C_70_Years_Porsche_Sports_Car%2C_Berlin_%281X7A3904%29.jpg"
cat >>"$tmp/out.dart" <<'EOF'

// Embraer EMB 110 in flight, Wikimedia Commons, CC BY-SA 2.0:
// https://commons.wikimedia.org/wiki/File:Embraer_EMB_110_in_flight_(105091729).jpg
EOF
photo planeJpeg 0 "$commons/3/38/Embraer_EMB_110_in_flight_%28105091729%29.jpg/500px-Embraer_EMB_110_in_flight_%28105091729%29.jpg"
cat >>"$tmp/out.dart" <<'EOF'

// People seen from behind, Wikimedia Commons, downscaled. Biswarup Ganguly, CC BY 3.0:
// https://commons.wikimedia.org/wiki/File:Man_Standing_-_Back_View_-_Kolkata_2011-01-25_0236.JPG
EOF
photo rearManJpeg 520 "$commons/3/3f/Man_Standing_-_Back_View_-_Kolkata_2011-01-25_0236.JPG/960px-Man_Standing_-_Back_View_-_Kolkata_2011-01-25_0236.JPG"
cat >>"$tmp/out.dart" <<'EOF'

// JFVelasquez Floro, CC0:
// https://commons.wikimedia.org/wiki/File:9777Walking_men_shouldercarrying_seen_from_behind_in_Bulacan_03.jpg
EOF
photo rearWalkerJpeg 640 "$commons/3/31/9777Walking_men_shouldercarrying_seen_from_behind_in_Bulacan_03.jpg/960px-9777Walking_men_shouldercarrying_seen_from_behind_in_Bulacan_03.jpg"
cat >>"$tmp/out.dart" <<'EOF'

// Solomon203, CC BY-SA 4.0 (faces pixelated by the author):
// https://commons.wikimedia.org/wiki/File:Cosplayer_of_Annin_Miru_walking_seen_from_behind_20240204.jpg
EOF
photo rearCrowdJpeg 640 "$commons/7/76/Cosplayer_of_Annin_Miru_walking_seen_from_behind_20240204.jpg/500px-Cosplayer_of_Annin_Miru_walking_seen_from_behind_20240204.jpg"

mv "$tmp/out.dart" "$out"
echo "Wrote $out"
