#!/bin/bash
#
# This script has basic functions like a random password generator
LXC_RANDOMPWD=32

random_password() {
    set +o pipefail
    C_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c${LXC_RANDOMPWD}
}