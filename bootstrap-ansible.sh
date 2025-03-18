#!/bin/bash
#
# SOC2 Compliance: Ansible Bootstrap Script (Revised)
# Purpose: Initial setup to install Ansible and securely clone the Ansible playbook repository
# Last updated: 2025-03-14
#
# CHANGE LOG:
# - Converted most variable and function names to snake_case (for consistency).
# - Optionally use dist-upgrade instead of upgrade (commented out).
# - Optionally enable 'StrictHostKeyChecking accept-new' instead of 'no'.

show_help() {
    echo "SOC2 Ansible Bootstrap Script (Revised)"
    echo "======================================="
    echo "This script prepares a server for SOC2 compliance using Ansible by:"
    echo "  - Installing Ansible, Git and required dependencies"
    echo "  - Setting up SSH authentication for GitHub"
    echo "  - Cloning your private SOC2 Ansible playbook repository"
    echo ""
    echo "Usage: $0 [--help]"
    echo ""
    exit 0
}

# Exit on any error
set -e

# Parse command line arguments
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    show_help
fi

# Directories and files
log_dir="/var/log/soc2_setup"
mkdir -p "$log_dir"
chmod 750 "$log_dir"
log_file="$log_dir/ansible_bootstrap_$(date +%Y%m%d_%H%M%S).log"

# Function for logging
log_message() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$log_file"
}

log_message "Starting SOC2 Ansible bootstrap process"

# Collect system and user information for logging
log_message "System information:"
if command -v lsb_release >/dev/null 2>&1; then
    log_message "$(lsb_release -a 2>/dev/null)"
else
    log_message "$(cat /etc/os-release 2>/dev/null || true)"
fi
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
apt-get update

# Upgrade packages (uncomment the dist-upgrade line if preferred)
# log_message "Upgrading system packages (dist-upgrade)"
# apt-get dist-upgrade -y
log_message "Upgrading system packages (upgrade)"
apt-get upgrade -y

# Install essential packages
log_message "Installing essential packages"
apt-get install -y git curl wget apt-transport-https ca-certificates gnupg \
                   openssh-client software-properties-common python3 python3-pip

# Install Ansible
log_message "Adding Ansible repository"
add-apt-repository --yes --update ppa:ansible/ansible

log_message "Installing Ansible"
apt-get install -y ansible

# Install Ansible extras
log_message "Installing Ansible requirements"
apt-get install -y python3-jmespath python3-pymysql ansible-lint

# Verify installations
if ! command -v git >/dev/null 2>&1; then
    log_message "ERROR: Git installation failed"
    exit 1
fi
if ! command -v ansible >/dev/null 2>&1; then
    log_message "ERROR: Ansible installation failed"
    exit 1
fi

ansible_version=$(ansible --version | head -n1)
log_message "Installed $ansible_version"
echo "Successfully installed $ansible_version"

# Prompt for Git user information
echo ""
echo "Please enter the name to use for Git commits (e.g., 'Jane Smith'):"
read -r git_user_name

echo "Please enter the email to use for Git commits (e.g., 'jane.smith@company.com'):"
read -r git_user_email

# Basic email validation
if ! echo "$git_user_email" | grep -E "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" > /dev/null; then
    echo "Warning: The email address doesn't appear to be valid. Continuing anyway..."
    log_message "WARNING: Potentially invalid email format: $git_user_email"
fi

# Configure Git
log_message "Configuring Git with user: $git_user_name, email: $git_user_email"
git config --global user.name "$git_user_name"
git config --global user.email "$git_user_email"

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
  # CHANGE: For better security, consider 'StrictHostKeyChecking accept-new'
  StrictHostKeyChecking no
EOF

chmod 600 ~/.ssh/config

# Create base directory for SOC2 Ansible configuration
ansible_dir="/opt/soc2-ansible"
log_message "Creating base directory: $ansible_dir"
mkdir -p "$ansible_dir"

repo_url="git@github.com:GetDATS/DATS-SoC2-Server-Setup-Ansible.git"
log_message "Using repository: $repo_url"

# Clone the repository
log_message "Attempting to clone repository: $repo_url"
if git clone "$repo_url" "$ansible_dir"; then
    log_message "Repository cloned successfully"
    chmod 750 "$ansible_dir"
    find "$ansible_dir" -type f -name "*.yml" -exec chmod 640 {} \;

    # Create or ensure ansible.log is protected
    touch /var/log/ansible.log
    chmod 640 /var/log/ansible.log
    chown root:adm /var/log/ansible.log
else
    log_message "ERROR: Failed to clone the repository: $repo_url"
    echo "Failed to clone the repository. Possible causes:"
    echo "  - The deploy key may not have been added to the GitHub repository"
    echo "  - The SSH configuration may not be correct"
    echo ""
    echo "Check the SSH connection by running: ssh -T git@github.com"
    exit 1
fi

log_message "Ansible bootstrap completed successfully"
echo ""
echo "SOC2 Ansible bootstrap complete!"
echo "SOC2 Ansible repository is located at: $ansible_dir"
echo ""
echo "To run the playbooks:"
echo "  cd $ansible_dir"
echo "  ansible-playbook playbooks/site.yml        # For all servers"
echo "  ansible-playbook playbooks/application.yml # For application servers only"
echo "  ansible-playbook playbooks/monitoring.yml  # For monitoring servers only"
echo ""
echo "For security, consider deleting the SSH deploy key after setup is complete:"
echo "  rm ~/.ssh/github_deploy_key"
echo ""
echo "SOC2 Ansible bootstrap completed at: $(date)"
exit 0
