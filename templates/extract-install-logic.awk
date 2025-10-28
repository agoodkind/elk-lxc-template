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

# Handle EMBED_FILE markers (creates new file with >)
/^# EMBED_FILE:/ {
	# Extract source and destination from: # EMBED_FILE: source -> dest
	line_text = $0
	sub(/^# EMBED_FILE: /, "", line_text)
	arrow_pos = index(line_text, " -> ")
	source = substr(line_text, 1, arrow_pos - 1)
	dest = substr(line_text, arrow_pos + 4)
	
	print "cat > " dest " << 'ELKEOF'"
	
	# Read and output the source file
	while ((getline file_line < source) > 0) {
		print file_line
	}
	close(source)
	
	print "ELKEOF"
	print ""
	next
}

# Handle EMBED_FILE_APPEND markers (appends to existing file with >>)
/^# EMBED_FILE_APPEND:/ {
	# Extract source and destination from: # EMBED_FILE_APPEND: source -> dest
	line_text = $0
	sub(/^# EMBED_FILE_APPEND: /, "", line_text)
	arrow_pos = index(line_text, " -> ")
	source = substr(line_text, 1, arrow_pos - 1)
	dest = substr(line_text, arrow_pos + 4)
	
	print "cat >> " dest " << 'ELKEOF'"
	
	# Read and output the source file
	while ((getline file_line < source) > 0) {
		print file_line
	}
	close(source)
	
	print "ELKEOF"
	print ""
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

