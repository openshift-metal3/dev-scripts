#!/bin/bash

set -ex

make | sed -e 's/.*auth.*/*** PULL_SECRET ***/g'
