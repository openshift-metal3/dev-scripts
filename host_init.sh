#!/bin/bash
# This script is meant to be ran with sudo privileges as a non-root user.
# Requires the pull-secret file to be present in the current directory.
# The script will:
# 1. Configure passwordless sudo for the user
# 2. Invoke subscription-manager in order to register and activate the subscription (in case of RHEL)
# 3. Install new packages (like Git, text editor, shell and so on)
# 4. Clone the dev-scripts repository
# 5. Add the shared secret into the personal user pull-secret file (Get it at https://cloud.redhat.com/openshift/install/pull-secret)
# 6. Create a config file and apply basic configuration (including pull-secret and install directory)
# 7. Create world-readable dev-scripts directory under /home (as by default it's the largest volume)

# --- Config, please edit according to personal preferences:
shell="zsh"       # Enter the name of the package, as it will be directly piped into yum
text_editor="vim" # Enter the name of the package, as it will be directly piped into yum
subs_username=""  # RH Subscription username
subs_password=""  # RH Subscription password
# --- End config

# Alias for text styles
bold=$(tput bold)
normal=$(tput sgr0)
warning=$(tput setaf 3)

# Vars
user=$(logname)
home_dir=$(eval echo ~$user)

# Warnings / Errors
error=false
sudo -v
if [ $? -ne 0 ]; then
    echo "${bold}${warning}Please run the script as a sudo user${normal}"
    error=true
fi
if [ ! -f "pull-secret" ]; then
    echo "${bold}${warning}Please place the pull-secret file in the current directory${normal}"
    error=true
fi
# Exit in case of an error
if [ "$error" = true ]; then
    exit 1
fi

# Passwordless sudo (if not set up yet)
if ! grep -xq "$user\s*ALL=(ALL)\s*NOPASSWD:\s*ALL" /etc/sudoers; then
    echo "${bold}Enabling passwordless sudo for $user${normal}"
    echo "$user  ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers
fi

# Subscription manager (in case of RHEL)
if [ -f "/etc/redhat-release" ] && grep -q "Red Hat Enterprise Linux" /etc/redhat-release; then
    if [ -z "$subs_username" ] || [ -z "$subs_password" ]; then
        echo "${bold}${warning}Please edit the prefereces in this file before running it${normal}"
        exit 1
    fi
    subscription-manager list | grep -q Subscribed
    if [ $? -ne 0 ]; then
        echo "${bold}Registering and activating subscription${normal}"
        subscription-manager register --username $subs_username --password $subs_password
        subscription-manager attach
    fi
fi

# Packages
echo "${bold}Updating existing packages${normal}"
yum update -y
echo "${bold}Installing new packages${normal}"
pkgs=("git" "make" "wget" "tmux" "jq" $shell $text_editor)
install_cmd="yum install -y ${pkgs[@]}"
eval $install_cmd
[ $? -eq 0 ] || (echo "${bold}${warning}Failed:${normal} ${install_cmd}" && exit 1)

# Dev-Scripts
if [ -d "dev-scripts" ]; then
    git -C dev-scripts pull
else
    echo "${bold}Cloning dev-scripts repository${normal}"
    git clone https://github.com/openshift-metal3/dev-scripts
fi

# Dev-Scripts config
config_file="dev-scripts/config_$user.sh"
if [ ! -f "$config_file" ]; then
    cp dev-scripts/config_example.sh $config_file
fi
workdir='export WORKING_DIR=${WORKING_DIR:-"/home/dev-scripts"}'
if ! grep -xq "${workdir}" $config_file; then
    echo $workdir >>$config_file
fi

# Pull secret
if  ! grep -xq "registry.svc.ci.openshift.org" $home_dir/pull-secret; then
    echo "${bold}Configuring the pull secret${normal}"
    shared_secret='{"registry.svc.ci.openshift.org": {
        "auth": "PLACE_SECRET_HERE"
    }}'
    cat pull-secret | jq --argjson secret $shared_secret '.["auths"] + $secret' >$home_dir/pull-secret
    original_string="PULL_SECRET=''"
    replace_string="PULL_SECRET='$(cat ${home_dir}/pull-secret)'"
    sed -i "s~$original_string~$replace_string~g" $home_dir/dev-scripts/config_$user.sh
fi

# Workdir
mkdir /home/dev-scripts 2>/dev/null && echo "${bold}Creating workdir${normal} at /home/dev-scripts"
chmod 755 /home/dev-scripts
chown $user /home/dev-scripts

# Success output
echo "${bold}All done, to install dev-scripts please run:${normal}"
echo "make -C $home_dir/dev-scripts"
