# SOC2 Server Bootstrap

This repository contains a bootstrap script for setting up SOC2-compliant servers on Ubuntu 24.04 LTS.

## What does this script do?

This bootstrap script:
1. Installs Git and SSH client
2. Sets up SSH authentication for GitHub
3. Clones your private SOC2 configuration repository
4. Creates the initial directory structure if needed

## Usage

# Step 1: Download the script
curl -sSL https://raw.githubusercontent.com/GetDATS/DATS-SoC2-Server-Bootstrap/main/bootstrap.sh -o bootstrap.sh

# Step 2: Make it executable
chmod +x bootstrap.sh

# Step 3: Execute it
sudo ./bootstrap.sh
