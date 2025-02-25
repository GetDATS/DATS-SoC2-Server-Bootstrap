# SOC2 Server Bootstrap

This repository contains a bootstrap script for setting up SOC2-compliant servers on Ubuntu 24.04 LTS.

## What does this script do?

This bootstrap script:
1. Installs Git and SSH client
2. Sets up SSH authentication for GitHub
3. Clones your private SOC2 configuration repository
4. Creates the initial directory structure if needed

## Usage

```bash
curl -sSL https://raw.githubusercontent.com/GetDATS/DATS-SoC2-Server-Config/main/bootstrap.sh | sudo bash
