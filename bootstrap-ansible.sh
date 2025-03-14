#!/bin/bash
#
# SOC2 Compliance: Ansible Bootstrap Script
# Purpose: Initial setup to install Ansible and securely clone the Ansible playbook repository
# Last updated: 2025-03-14
#
# This script:
# 1. Updates the system
# 2. Installs Git, SSH client, and Ansible
# 3. Sets up secure SSH authentication for GitHub
# 4. Clones the private SOC2 Ansible configuration repository
# 5. Sets up initial logging

# Help function for self-documentation
show_help() {
    echo "SOC2 Ansible Bootstrap Script"
    echo "============================="
    echo "This script prepares a server for SOC2 compliance using Ansible by:"
    echo "  - Installing Ansible, Git and required dependencies"
    echo "  - Setting up SSH authentication for GitHub"
    echo "  - Cloning your private SOC2 Ansible playbook repository"
    echo ""
    echo "You will need:"
    echo "  - A GitHub deploy key (SSH private key)"
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
chmod 750 $LOGDIR
LOGFILE="$LOGDIR/ansible_bootstrap_$(date +%Y%m%d_%H%M%S).log"

# Function for logging
log_message() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a $LOGFILE
}

log_message "Starting SOC2 Ansible bootstrap process"

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

# Update system packages
log_message "Upgrading package required updates"
echo "Upgrading system packages. This may take a while..."
apt-get upgrade -y

# Install essential packages
log_message "Installing essential packages"
apt-get install -y git curl wget apt-transport-https ca-certificates gnupg openssh-client software-properties-common python3 python3-pip

# Install Ansible
log_message "Installing Ansible"
echo "Installing Ansible. This may take a moment..."

# Add Ansible repository for latest version
add-apt-repository --yes --update ppa:ansible/ansible
apt-get install -y ansible

# Install Ansible requirements
log_message "Installing Ansible requirements"
apt-get install -y python3-jmespath python3-pymysql ansible-lint

# Verify installations
log_message "Verifying installations"
which git > /dev/null 2>&1 || { log_message "ERROR: Git installation failed"; echo "Git installation failed."; exit 1; }
which ansible > /dev/null 2>&1 || { log_message "ERROR: Ansible installation failed"; echo "Ansible installation failed."; exit 1; }

# Show installed versions
ANSIBLE_VERSION=$(ansible --version | head -n1)
log_message "Installed $ANSIBLE_VERSION"
echo "Successfully installed $ANSIBLE_VERSION"

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

# Create base directory for SOC2 Ansible configuration
ANSIBLE_DIR="/opt/soc2-ansible"
log_message "Creating base directory: $ANSIBLE_DIR"
mkdir -p $ANSIBLE_DIR

# Use fixed repository URL
REPO_URL="git@github.com:GetDATS/DATS-SoC2-Server-Setup-Ansible.git"
log_message "Using repository: $REPO_URL"

# Clone the repository
log_message "Attempting to clone repository: $REPO_URL"
echo "Cloning SOC2 Ansible repository..."

if git clone $REPO_URL $ANSIBLE_DIR; then
    log_message "Repository cloned successfully"

    # Set proper permissions on the Ansible directory
    chmod 750 $ANSIBLE_DIR

    # Make all playbook files accessible
    find $ANSIBLE_DIR -type f -name "*.yml" -exec chmod 640 {} \;
    log_message "Set proper permissions on Ansible playbooks"

    # Create ansible.cfg if it doesn't exist
    if [ ! -f "$ANSIBLE_DIR/ansible.cfg" ]; then
        log_message "Creating basic ansible.cfg configuration"
        cat > "$ANSIBLE_DIR/ansible.cfg" << 'EOF'
[defaults]
inventory = inventory/hosts
host_key_checking = False
retry_files_enabled = False
roles_path = roles
log_path = /var/log/ansible.log
callback_whitelist = profile_tasks, timer

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False
EOF
        chmod 640 "$ANSIBLE_DIR/ansible.cfg"
    fi

    # Make sure the ansible.log file exists and has proper permissions
    touch /var/log/ansible.log
    chmod 640 /var/log/ansible.log
    chown root:adm /var/log/ansible.log

else
    log_message "ERROR: Failed to clone the repository: $REPO_URL"
    echo "Failed to clone the repository. This could be due to:"
    echo "  - The deploy key may not have been added to the GitHub repository"
    echo "  - The SSH configuration may not be correct"
    echo ""
    echo "Check the SSH connection by running: ssh -T git@github.com"
    echo "If that fails, verify your key is working correctly."
    exit 1
fi

log_message "Ansible bootstrap completed successfully"
echo ""
echo "SOC2 Ansible bootstrap complete!"
echo "SOC2 Ansible repository is located at: $ANSIBLE_DIR"
echo ""
echo "To run the playbooks:"
echo "  cd $ANSIBLE_DIR"
echo "  ansible-playbook playbooks/site.yml  # For all servers"
echo "  ansible-playbook playbooks/application.yml  # For application servers only"
echo "  ansible-playbook playbooks/monitoring.yml  # For monitoring servers only"
echo ""
echo "For security, you may want to delete the SSH deploy key after setup is complete:"
echo "rm ~/.ssh/github_deploy_key"
echo ""
echo "SOC2 Ansible bootstrap completed at: $(date)"

exit 0