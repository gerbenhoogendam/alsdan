#!/bin/bash
# Compileert de firmware en zet de delen klaar voor de "Zet de firmware op de ESP32"-knop in de webapp.
# Eenmalig nodig: brew install arduino-cli; arduino-cli config init --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
#                 arduino-cli core update-index; arduino-cli core install esp32:esp32; arduino-cli lib install "Adafruit NeoPixel" VL53L1X
# Rechtstreeks uploaden zonder de webapp: arduino-cli upload -p /dev/cu.usbserial-XXXX --fqbn esp32:esp32:esp32 firmware/alsdan
set -e
cd "$(dirname "$0")/.."
arduino-cli compile --fqbn esp32:esp32:esp32 --export-binaries firmware/alsdan
B=firmware/alsdan/build/esp32.esp32.esp32
cp "$B/alsdan.ino.bootloader.bin" web/firmware/bootloader.bin
cp "$B/alsdan.ino.partitions.bin" web/firmware/partitions.bin
cp "$B/boot_app0.bin" web/firmware/boot_app0.bin
cp "$B/alsdan.ino.bin" web/firmware/alsdan.bin
echo "Firmware klaar in web/firmware/"
