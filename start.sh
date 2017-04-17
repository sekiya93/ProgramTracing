#!/bin/sh
kill `ps awx | grep placku[p] | awk '{print $1}'`
sleep 5
plackup tracing.psgi >> tracing.log 2>&1 &
