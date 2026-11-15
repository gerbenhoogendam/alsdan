#!/bin/bash
# Dubbelklik: start de Als-Dan webapp en opent hem in Chrome.
# (Via een echte http-adres, want de knop die de firmware op de ESP32 zet werkt niet vanaf een file://-pagina.)
cd "$(dirname "$0")/web"
python3 ../scripts/serve.py >/dev/null 2>&1 &
SERVER=$!
sleep 1
open -a "Google Chrome" "http://localhost:8321" 2>/dev/null || open "http://localhost:8321"
echo "Als-Dan draait op http://localhost:8321 — sluit dit venster om te stoppen."
trap "kill $SERVER" EXIT
wait $SERVER
