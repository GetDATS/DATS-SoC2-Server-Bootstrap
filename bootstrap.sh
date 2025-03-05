#!/bin/bash
#
# SOC2 Compliance: Secure Bootstrap Script
# Purpose: Initial setup to install Git and securely clone the private configuration repository
# Last updated: 2025-02-25
#
# This script:
# 1. Updates the system
# 2. Installs Git and SSH client
# 3. Sets up secure SSH authentication for GitHub
# 4. Clones the private SOC2 configuration repository
# 5. Sets up initial logging

# Help function for self-documentation
show_help() {
    echo "SOC2 Bootstrap Script"
    echo "====================="
    echo "This script prepares a server for SOC2 compliance by:"
    echo "  - Installing Git and required dependencies"
    echo "  - Setting up SSH authentication for GitHub"
    echo "  - Cloning your private SOC2 configuration repository"
    echo ""
    echo "You will need:"
    echo "  - A GitHub deploy key (SSH private key)"
    echo "  - Your private GitHub repository URL (in SSH format)"
    echo ""
    echo "Usage: $0 [--help]"
    echo ""
    exit 0
}

# Parse command line arguments
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    show_help
fi

# Exit on any error
set -e

# Create log directory
LOGDIR="/var/log/soc2_setup"
mkdir -p $LOGDIR
LOGFILE="$LOGDIR/bootstrap_$(date +%Y%m%d_%H%M%S).log"

# Function for logging
log_message() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a $LOGFILE
}

log_message "Starting SOC2 server bootstrap process"

# Collect system and user information for logging
log_message "System information:"
log_message "$(lsb_release -a 2>/dev/null || cat /etc/os-release)"
log_message "Kernel: $(uname -r)"
log_message "Hostname: $(hostname)"
log_message "Script executed by user: $(whoami)"
if [ -n "$SUDO_USER" ]; then
    log_message "Real user behind sudo: $SUDO_USER"
else
    log_message "Script appears to be run directly as root (no sudo detected)"
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_message "ERROR: This script must be run as root"
    echo "This script must be run as root. Try using sudo."
    exit 1
fi

# Update package lists
log_message "Updating package lists"
echo "Updating system packages. This may take a while..."
apt-get update

# Update package lists
log_message "Upgrading package required updates"
echo "Upgrading system packages. This may take a while..."
apt-get upgrade -y

# Install essential packages
log_message "Installing essential packages"
apt-get install -y git curl wget apt-transport-https ca-certificates gnupg openssh-client

# Verify Git installation
log_message "Verifying Git installation"
which git > /dev/null 2>&1
if [ $? -ne 0 ]; then
    log_message "ERROR: Git installation failed"
    echo "Git installation failed. Please check your system and try again."
    exit 1
fi

# Prompt for Git user information
echo ""
echo "Please enter the name to use for Git commits (e.g., 'Jane Smith'):"
read GIT_USER_NAME

echo "Please enter the email to use for Git commits (e.g., 'jane.smith@company.com'):"
read GIT_USER_EMAIL

# Validate email format (basic check)
if ! echo "$GIT_USER_EMAIL" | grep -E "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" > /dev/null; then
    echo "Warning: The email address doesn't appear to be valid. Continuing anyway..."
    log_message "WARNING: Potentially invalid email format: $GIT_USER_EMAIL"
fi

# Set up Git configuration
log_message "Configuring Git with user: $GIT_USER_NAME, email: $GIT_USER_EMAIL"
git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"

# Set up SSH directory
log_message "Setting up SSH directory"
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Prompt for SSH deploy key
echo ""
echo "Please paste your GitHub deploy key (private key) for the SOC2 repository:"
echo "Press Ctrl+D on a new line when finished"
echo ""

cat > ~/.ssh/github_deploy_key
chmod 600 ~/.ssh/github_deploy_key

# Backup existing SSH config if present
if [ -f ~/.ssh/config ]; then
    log_message "Backing up existing SSH config"
    cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d_%H%M%S)
fi

# Configure SSH for GitHub
log_message "Configuring SSH for GitHub access"
cat > ~/.ssh/config << 'EOF'
Host github.com
  IdentityFile ~/.ssh/github_deploy_key
  StrictHostKeyChecking no
EOF

chmod 600 ~/.ssh/config

# Create base directory for SOC2 configuration
SOC2_DIR="/opt/soc2-server-config"
log_message "Creating base directory: $SOC2_DIR"
mkdir -p $SOC2_DIR

# Prompt for GitHub repository URL
echo ""
echo "Please enter your GitHub repository URL (in SSH format):"
echo "Example: git@github.com:GetDATS/DATS-SoC2-Server-Config.git"
read REPO_URL

# Clone the repository
log_message "Attempting to clone repository: $REPO_URL"
echo "Cloning SOC2 configuration repository..."

if git clone $REPO_URL $SOC2_DIR; then
    log_message "Repository cloned successfully"
    
    # Make all scripts executable
    find $SOC2_DIR/installers -name "*.sh" -exec chmod +x {} \;
    log_message "Made all installer scripts executable"

    # Make all tools scripts executable
    find $SOC2_DIR/base/tools/backups -name "*.sh" -exec chmod +x {} \;
    log_message "Made all backup tools scripts executable"
    
else
    log_message "ERROR: Failed to clone the repository: $REPO_URL"
    echo "Failed to clone the repository. This could be due to:"
    echo "  - The deploy key may not have been added to the GitHub repository"
    echo "  - The repository URL may be incorrect"
    echo "  - The SSH configuration may not be correct"
    echo ""
    echo "Check the SSH connection by running: ssh -T git@github.com"
    echo "If that fails, verify your key is working correctly."
    exit 1
fi

log_message "Bootstrap completed successfully"
echo ""
echo "SOC2 server bootstrap complete!"
echo "SOC2 configuration repository is located at: $SOC2_DIR"
echo ""
echo "Next steps:"
echo "1. Navigate to the repository: cd $SOC2_DIR"
echo "2. Begin the installation process with: ./installers/00_prepare_ssh.sh"
echo ""
echo "For security, you may want to delete the SSH deploy key after setup is complete:"
echo "rm ~/.ssh/github_deploy_key"
echo ""
echo "SOC2 server bootstrap completed at: $(date)"

exit 0
