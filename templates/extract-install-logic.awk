# AWK script to extract installation logic from install-steps.sh
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# License: Apache-2.0
#
# This script processes install-steps.sh and transforms it into the format
# expected by the Proxmox community script framework.

BEGIN { 
	in_step = 0
	step_name = ""
}

# Match STEP markers and generate msg_info/msg_ok calls
/^# STEP:/ {
	if (in_step) {
		print "msg_ok \"" substr(step_name, 2) "\""
		print ""
	}
	step_name = substr($0, 8)
	print "msg_info \"" step_name "\""
	in_step = 1
	next
}

# Skip header comments and blank lines
/^#!/ || /^# Copyright/ || /^# Author/ || /^# License/ || /^#$/ || /^# Installation steps/ || /^# This file/ || /^# 1\./ || /^# 2\./ {
	next
}

# Skip empty lines
/^$/ {
	next
}

# Prefix apt-get commands with $STD for silent execution
/^apt-get / {
	print "$STD " $0
	next
}

# Pass through all other lines
{
	print $0
}

# Close final step
END {
	if (in_step) {
		print "msg_ok \"" substr(step_name, 2) "\""
	}
}

