#!/usr/bin/env bash
# Pracovný priestor prípadu: zmena košíka a krok integration v kontajneri, ktorý nebeží — kontrola dá PARTIAL.
exec bash "$(dirname "$0")/../fixtures/scaffold.sh" --config container --change cart-count
