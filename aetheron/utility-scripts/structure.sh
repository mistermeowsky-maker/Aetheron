#!/bin/bash
BASE=~/aetheron
echo "=== AETHERON STRUCTURE ===" > overview.txt
tree -a $BASE >> overview.txt
echo -e "\n=== SERVER-SETUP.SH ===" >> overview.txt
cat $BASE/server-setup.sh >> overview.txt
echo -e "\n=== COMMON.SH ===" >> overview.txt  
cat $BASE/scripts/common.sh >> overview.txt
