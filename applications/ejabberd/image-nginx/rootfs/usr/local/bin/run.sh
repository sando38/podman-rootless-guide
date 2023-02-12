#!/bin/sh

# check if password is a "file" or variable
if [ -n "${HTTP_SECRET_FILE:-}" ]; then
    # create secret from file
    export HTTP_SECRET=$(cat "$HTTP_SECRET_FILE")
elif [ -z "${HTTP_SECRET:-}" ]; then
    echo ">>> No DB_PASSWORD or DB_PASSWORD_FILE is set"
fi

sed -i "s|my \$external_secret = \'.*\';|my \$external_secret = \'$HTTP_SECRET\';|" \
        $(find /usr/local/lib -name upload.pm)

exec nginx
