#! /bin/bash
#############################################################################################
#                                                                                           #
#                    ==================================================                     #
#                =======        Almigthy DisplayLink Manager        =======                 #
#                    ==================================================                     #
#                                                                                           #
# DESCRIPTION:                                                                              #
# This script (sort of) automates the DisplayLink driver installation processs.             #
#                                                                                           #
# It has the following options:                                                             #
#   --install <version>:                                                                    #
#           downloads the latest (or specified) driver from the official Synaptics website  #
#           and starts the official installer                                               #
#   --list:                                                                                 #
#           scrapes available driver versions from the offical website                      #
#   --uninstall:                                                                            #
#           uses the official uninstaller to remove the driver from the system              #
#   --sign:                                                                                 #
#           signes the EVDI kernel module after the installation in case the installer      #
#           fails to do so (Necessary only with Secure Boot).                               #
#   --remove-evdi:                                                                          #
#           removes corrupted installation of the evdi kernel module. Do NOT use this to    #
#           uninstall sucessfuly installed driver, it is just an emergency option to remove #
#           installation deadlock.                                                          #
#                                                                                           #
# NOTES:                                                                                    #
# To upgrade the driver, first uninstall the current one, reboot and install new one.       #
#                                                                                           #
#############################################################################################

# Script inputs
ACTION=${1}
PARAM=${2}

# Settings
PATH_TO_MOKKEY="${HOME}/.config/mokkey/"        # This key can be reused for future upgrades
KEEP_DOWNLOADED_DRIVERS="false"                 # When set true script will not remove driver archives
DRIVER_INSTALLER_PATH=$(pwd)


# just a bit of styling for better readability
YELLOW='\x1b[38;2;255;255;0m'
RED='\x1b[38;2;227;11;11m'
CLEARFORMAT='\033[0m'


# The entrypoint of the script
function main {
    case ${ACTION} in
    "--install"| -i)
        prepare_installer_folder
        download_driver ${PARAM}
        install_driver
        ;;
    "--list"| -l)
        list_driver_releases
        ;;
    "--uninstall"| -u)
        uninstall_driver
        ;;
    "--sign" | -s)
        sign_evdi_kernel_module
        ;;
    "--remove-evdi" | -re)
        remove_evdi_kernel_module
        ;;
    "--help" | -h)
        print_help
        ;;
    *)
        echo -e "${RED}Wrong or no parameter supplied. Use parameter  \"-h\" or \"--help\" to list available options${CLEARFORMAT}"
        ;;
    esac
}


# Finds the latest (or specified) version of the driver, downloads it and renames the file
function download_driver {
    local selected_version=${1}

    # Install CURL if not already present on the system
    if [[ "$(which curl)" == "" ]] || [[ "$(which curl)" =~ *"not found"* ]]; then
        echo -e "${RED}Curl is not available in the system. It is necessary to gather driver info from Synaptics Website. ${CLEARFORMAT}"

        request_consent "Do you wish to install curl?"

        sudo apt update
        sudo apt install curl
    fi

    # scrape the whole html page for offline parsing
    scraped_synaptics_website=$(curl -s http://www.synaptics.com/products/displaylink-graphics/downloads/ubuntu)

    if [[ "${selected_version}" != "" ]]; then
        # Parse version-related data
        scraped_synaptics_website_segment=$(echo -e "${scraped_synaptics_website}" | grep "${selected_version}-")

        # check whether the data is available
        if [[ "${scraped_synaptics_website_segment}" == "" ]]; then
            exit_grace "${RED}Did not find version \"${selected_version}\" on the website! Sse --list to see available versions.${CLEARFORMAT}"
        fi

        # parse the date of the driver in the format required to compose a download link
        html_path_date_suffixed=${scraped_synaptics_website_segment#'     <a href="/sites/default/files/release_notes/'}
        html_path_date=${html_path_date_suffixed%%/*}
    else
        # parse the string of the latest version
        selected_version=$(echo -e "${scraped_synaptics_website}" | grep "Release: " | awk '{ print $2}' | sort | tail -n -1)

        # parse the date of the driver in the format required to compose a download link
        scraped_synaptics_website_segment=$(echo -e "${scraped_synaptics_website}" | grep "${selected_version}-" )
        html_path_date_suffixed=${scraped_synaptics_website_segment#'     <a href="/sites/default/files/release_notes/'}
        html_path_date=${html_path_date_suffixed%%/*}
    fi

    # compose the download link
    driver_download_link="http://www.synaptics.com/sites/default/files/exe_files/${html_path_date}/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu${selected_version}-EXE.zip"

    # prep less idiotic name for the downloaded driver archive
    file_version_sufix=$(echo ${selected_version} | tr "." "_")
    downloaded_file_name="driver${file_version_sufix}.zip"

    if [ ! -f "${downloaded_file_name}" ]; then
        # download and extract the driver archive
        wget ${driver_download_link} -O ${downloaded_file_name}
        # check that the file was succesfully downloaded
        if (( ${?} != 0 )); then
            exit_grace "${RED}Something went wrong during the download.${CLEARFORMAT}"
        fi
    else
        echo -e "${YELLOW}Driver was already downloaded. Extracting locally available file.${CLEARFORMAT}"
    fi

    unzip ${downloaded_file_name} -d displaylink_driver/
    # check that the file was succesfully extracted
    if (( ${?} != 0 )); then
        exit_grace "${RED}Something went wrong during the driver archive extraction.${CLEARFORMAT}"
    fi
}

# Makes a folder to minimise the file mess
function prepare_installer_folder {
    # check if the installation folder already exists
    if [[ ! -d displaylink_installer ]]; then
        mkdir ${DRIVER_INSTALLER_PATH}/displaylink_installer
    fi
    cd ${DRIVER_INSTALLER_PATH}/displaylink_installer

    # check if the folder for driver extraction already exists
    if [[ -d displaylink_driver ]]; then
        echo -e "${RED}Found a folder with already extracted driver files. This is unexpected. Either previous run of this installer did not finish or the folder content is unrelated to his script.${CLEARFORMAT}"
        echo -e "${RED}The folder contains:${CLEARFORMAT}"

        echo -e ""
        ls ./displaylink_driver
        echo -e ""

        request_consent "Do you wish to remove the folder and continue with the installation?"

        cleanup driver

        mkdir displaylink_driver
    fi
}

# Basically just launches the official installer, creates folders and adds some useful tips
function install_driver {
    # Verify that no EVDI module is currently installed as the installation would fail
    if [[ "$(sudo dkms status | grep evdi)" != *"not found"* ]]; then
        exit_grace "${RED}EVDI kernel module is already installed in this system. Either uninstall the present DisplayLink driver or remove the evdi module. See --help.${CLEARFORMAT}"
    fi

    # Run official installer
    echo -e "${YELLOW}Driver installation is about to begin.${CLEARFORMAT}"
    echo -e "${YELLOW}Depending on your system configuration the installer may try to generate MOK key and sign the kernel module automatically. If the installation gets stuck on \"Installing EVDI DKMS module\" for a few minutes, try resizing the terminal window, then an interactive prompt about MOK should appear. In this case the prompt seems to re-draw only with window resize event so resize the window after every action to see the result.${CLEARFORMAT}"

    request_consent

    sudo ./displaylink_driver/*.run --accept
    echo -e "${YELLOW}Now reboot your computer. If you won't be able to connect your PC to the DisplayLink device after the reboot, check out \"dmesg\" whether it detects \"Logitech Logi Human interface\" and whether there are any \"Lockdown: modprobe: unsigned module loading is restricted; see man kernel_lockdown.7\" errors, which would imply Secure Boot is prohibiting the kernel module - in this case run this script again with param --sign. (use --help to read details)${CLEARFORMAT}"

    cleanup
}


# Removes extracted driver files
function cleanup {
    local mode=${1}

    if [[ "${KEEP_DOWNLOADED_DRIVERS}" == "true" ]] || [[ "${mode}" == "driver" ]]; then
        rm -r ./displaylink_driver
    else
        rm -r ${DRIVER_INSTALLER_PATH}/displaylink_installer
    fi
}


# Checks whether the key was already generated so the script does not bloat the Secure Boot during upgrades/reinstalls
function prepare_key {
    # Make a folder to store the key. Persitant location is advisable as the key can be re-used
    if [[ ! -d ${PATH_TO_MOKKEY} ]]; then
        mkdir ${PATH_TO_MOKKEY}
    fi

    # Check whether the key does exist and create it if not
    if [[ ! -f "${PATH_TO_MOKKEY}/EvdiMOK.der" ]] && [[ ! -f "${PATH_TO_MOKKEY}/EvdiMOK.priv" ]]; then
        generate_key
    elif [[ -f "${PATH_TO_MOKKEY}/EvdiMOK.der" ]] && [[ -f "${PATH_TO_MOKKEY}/EvdiMOK.priv" ]]; then
        echo -e "${YELLOW}Found existing MOK key in the installation folder${CLEARFORMAT}"
        while true; do
            read -p "Do you wish to use this key? [y/n]: " yn
            case ${yn} in
                [Yy]*) break;;
                [Nn]*)
                    exit_grace "${YELLOW}If you wish to use a different key for signature, delete this one first. Also consider removing it from Secure Boot with \"mokutil --delete <key>\". You can find the correct key with \"mokutil --list-enrolled\"${CLEARFORMAT}"
                    ;;
                * ) echo "Please answer [y]es or [n]o.";;
            esac
        done
    elif [[ ! -f "${PATH_TO_MOKKEY}/EvdiMOK.der" ]] || [[ ! -f "${PATH_TO_MOKKEY}/EvdiMOK.priv" ]]; then
        exit_grace "${RED}EvdiMOK.der or EvdiMOK.priv is missing. Either remove the remaining file or supply the missing one to folder: \"${PATH_TO_MOKKEY}/\" and run this script again.${CLEARFORMAT}"
    fi
}


# Generates the user-generated key for kernel module signing
function generate_key {
    openssl req -new -x509 -newkey rsa:2048 -keyout "${PATH_TO_MOKKEY}/EvdiMOK.priv" -outform DER -out "${PATH_TO_MOKKEY}/EvdiMOK.der" -nodes -days 36500 -subj "/CN=EVDI_MOK_key/"
}


# Signs the EVDI kernel module with user-generated key in case the official installer fails
function sign_evdi_kernel_module {
    # Install the necessary software if not already present in the system
    if [[ "$(which mokutil)" == "" ]] || [[ "$(which mokutil)" =~ *"not found"* ]]; then
        echo -e "${RED}Mokutil utility is not available in the system. It is necessary to sign the driver. ${CLEARFORMAT}"
        request_consent "Do you wish to install mokutil?"
        sudo apt update
        sudo apt install mokutil
    fi

    prepare_key

    # Sign the kernel module with user-generated key
    # sudo kmodsign sha512 ./EvdiMOK.priv ./EvdiMOK.der /path/to/module is an alternative if sign-file is not available.
    sudo /usr/src/linux-headers-$(uname -r)/scripts/sign-file sha256 "${PATH_TO_MOKKEY}/EvdiMOK.priv" "${PATH_TO_MOKKEY}/EvdiMOK.der" $(modinfo -n evdi)

    # Check whether user-generated key was already enrolled, if not enroll it
    if [[ "$(mokutil --test-key "${PATH_TO_MOKKEY}/EvdiMOK.der")" == *"already enrolled"* ]]; then
        echo -e "${YELLOW}User-generated MOK key was already enrolled.${CLEARFORMAT}"
    else
        echo -e "${YELLOW}Supply a one-time password (At least 8 characters, ideally US keyboard friendly) that you will have to input after reboot${CLEARFORMAT}"
        sudo mokutil --import "${PATH_TO_MOKKEY}/EvdiMOK.der"
        echo -e "${YELLOW}Upon system reboot, you will need to perform MOK management. Choose Enroll MOK » Continue » Yes » Enter Password (the one you have just set) » Reboot.${CLEARFORMAT}"
        echo "Once the system boots up use \"sudo mokutil --list-enrolled | grep EVDI\" to verify that the key was sucessfuly imported. (It is in the --help, I don't expect you to remember the command)"
    fi
}


function remove_evdi_kernel_module {
    echo -e "${YELLOW}You are about to remove the evdi kernel module. Use this command ONLY if the driver installation fails because of existing evdi kernel module! If you wish to uninstall an existing driver or upgrade the driver, use corresponding options (use --help to read details) ${CLEARFORMAT}"
    request_consent

    if (( $(dkms status | wc -l) > 1 )); then
        echo -e "${RED}There is more then one EVDI module available, please remove them manuanlly.${CLEARFORMAT}"
    else
        evdi_module_to_remove=$(sudo dkms status | grep evdi | awk '{print $1}' | tr ',' ' ')
        sudo dkms remove ${evdi_module_to_remove} -a
    fi
}


# Requests a consent from the user to continue with a process
function request_consent {
    # Custom message can be specified if left empty default value is used
    inquery=${1}
    if [[ "${inquery}" == "" ]]; then
        inquery="Do you wish to continue?"
    fi

    while true; do
        read -p "${inquery} [y/n]: " yn
        case $yn in
            [Yy]*)
                break
                ;;
            [Nn]* )
                exit_grace "${YELLOW}Exiting script.${CLEARFORMAT}"
                ;;
            * ) echo "Please answer [y]es or [n]o.";;
        esac
    done
}


# Retrives the list of available driver versions from the official website
function list_driver_releases {
    # Install CURL if not already present on the system
    if [[ "$(which curl)" == "" ]] || [[ "$(which curl)" =~ *"not found"* ]]; then
        echo -e "${RED}Curl is not available in the system. It is necessary to gather driver info from Synaptics Website. ${CLEARFORMAT}"
        request_consent "Do you wish to install curl?"
        sudo apt update
        sudo apt install curl
    fi
    curl -s http://www.synaptics.com/products/displaylink-graphics/downloads/ubuntu | grep "Release: " | awk '{ print $2}' | sort
}


function uninstall_driver {
    echo -e "${YELLOW}You are about to uninstall displaylink driver. ${CLEARFORMAT}"
    request_consent
    sudo displaylink-installer uninstall
}


function exit_grace {
    local msg=${1}
    echo -e "${msg}"
    cleanup
    exit
}


function print_help {
    cat << EOF
    This script helps to simply and partially automate the DisplayLink driver installation.

    options:
        -i,  --install <version>    | Downloads and installs the driver; without <version>
                                      defaults to latest.
        -l,  --list                 | Lists all available driver releases.
        -u,  --uninstall            | Uninstall current driver.
        -s,  --sign                 | Signs the kernel module for usage with secure boot.
        -re, --remove-evdi          | Removes the incorrectly installed EVDI kernel module.
        -h,  --help                 | Outputs this message.

    Notes:
        - To upgrade the driver, first uninstall the current one, reboot and install new one

    Troubleshooting & tips:
        - To test succesfull MOK key enrollment:
            - execute: "sudo mokutil --list-enrolled | grep EVDI_MOK_key"
        - To check the kernel module is properly loaded:
            - execute: "sudo modinfo evdi"
        - Check out "dmesg":
            - whether it detects "Logitech Logi Human interface" if not good luck hunting
              down the right diversant
            - for any "Lockdown: modprobe: unsigned module loading is restricted" errors,
              which would imply Secure Boot is prohibiting the kernel module
        - To delete already enrolled key:
            - execute: "sudo mokutil --delete <key>"
            - use "sudo mokutil --list-enrolled" to find the right key
EOF
}

main
