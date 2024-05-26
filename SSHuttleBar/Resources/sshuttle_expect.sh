#!/usr/bin/expect -f

# Enable logging to a file for detailed debug output
# log_file /tmp/sshuttle_expect.log

# puts "Starting sshuttle_expect script..."

set timeout -1

# Get command line arguments
set password [lindex $argv 0]
set otp [lindex $argv 1]
set path_sshuttle [lindex $argv 2]

# puts "Arguments received:"
# puts "Password: $password"
# puts "OTP: $otp"
# puts "SSHuttle Path: $path_sshuttle"

# Start sshuttle
# puts "Starting sshuttle..."
spawn sudo $path_sshuttle -e "ssh -F /Users/andrea/.ssh/config" -r m1-gateway-mpcdf --dns 0/0

expect {
    -re ".*password: $" {
        # puts "Password prompt detected"
        send "$password\r"
        exp_continue
    }
    -re ".*Your OTP: $" {
        # puts "OTP prompt detected"
        send "$otp\r"
        exp_continue
    }
}

# Interact with the sshuttle process
interact

# Log when the interact block is finished
# puts "Interaction with sshuttle process finished"

# Close the log file explicitly
# close $log_file
