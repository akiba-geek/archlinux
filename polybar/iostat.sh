iostat -d 1 | while read line; do
    if [ "$line" = '' ]; then
        if [ "$prev_newline" -eq 1 ]; then
            echo
        else
            prev_newline=1
        fi
    else
        echo -n $line | awk '/^(sd|nvme)/ {printf "%s: %s ", $1, $2}'
        prev_newline=0
    fi
done
