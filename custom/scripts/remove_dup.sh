#!/bin/bash

remove_duplicates() {
    awk '
/^\.\.\./ { flag=1; print; next }
flag && !seen[$0]++ { print }
!flag { print }
' "$@" >"${*: -1}.dedup"
}

remove_duplicates "$@"
