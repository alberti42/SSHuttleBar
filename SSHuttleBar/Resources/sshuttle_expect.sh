#!/usr/bin/expect -f

set timeout -1

# Get command line arguments
set password [lindex $argv 0]
set otp [lindex $argv 1]
set path_sshuttle [lindex $argv 2]

# Start sshuttle
spawn sudo $path_sshuttle -e "ssh -F /Users/andrea/.ssh/config" -r m1-gateway-mpcdf --dns 0/0

expect {
    -re ".*password: $" {
        send "$password\r"
        exp_continue
    }
    -re ".*OTP: $" {
        send "$otp\r"
    }
}

interact
