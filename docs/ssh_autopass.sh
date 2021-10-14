USER=user
PASS=pass
 
# The server hostname.
SERVER=example.com
 

# Tell SSH to read in the output of the provided script as the password.
# We still have to use setsid to eliminate access to a terminal and thus avoid
# it ignoring this and asking for a password.
SSH_ASKPASS_SCRIPT=/tmp/ssh-askpass-script
cat > ${SSH_ASKPASS_SCRIPT} <<EOL
#!/bin/bash
echo "${PASS}"
EOL
chmod 744 ${SSH_ASKPASS_SCRIPT}

# Set up other items needed for OpenSSH to work.
# Set no display, necessary for ssh to play nice with setsid and SSH_ASKPASS.
export DISPLAY=:0
 
# The use of setsid is a part of the machinations to stop ssh
# prompting for a password.
export SSH_ASKPASS=${SSH_ASKPASS_SCRIPT}
setsid ssh ${SSH_OPTIONS} ${USER}@${SERVER} "${CMD}"
