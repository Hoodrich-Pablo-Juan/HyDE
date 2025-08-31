#!/usr/bin/env bash
# shellcheck disable=SC2154
#|---/ /+--------------------------+---/ /|#
#|--/ /-| Main installation script |--/ /-|#
#|-/ /--| Prasanth Rangan          |-/ /--|#
#|/ /---+--------------------------+/ /---|#

cat <<"EOF"

-------------------------------------------------
        .
       / \         _       _  _      ___  ___
      /^  \      _| |_    | || |_  _|   \| __|
     /  _  \    |_   _|   | __ | || | |) | _|
    /  | | ~\     |_|     |_||_|\_, |___/|___|
   /.-'   '-.\                  |__/

-------------------------------------------------

EOF

#--------------------------------#
# import variables and functions #
#--------------------------------#
scrDir="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
if ! source "${scrDir}/global_fn.sh"; then
    echo "Error: unable to source global_fn.sh..."
    exit 1
fi

#------------------#
# evaluate options #
#------------------#
flg_Install=0
flg_Restore=0
flg_Service=0
flg_DryRun=0
flg_Shell=0
flg_Nvidia=1
flg_ThemeInstall=1
flg_NoSddm=1  # Added flag to disable SDDM

while getopts idrstmnhx RunStep; do
    case $RunStep in
    i) flg_Install=1 ;;
    d)
        flg_Install=1
        export use_default="--noconfirm"
        ;;
    r) flg_Restore=1 ;;
    s) flg_Service=1 ;;
    n)
        # shellcheck disable=SC2034
        export flg_Nvidia=0
        print_log -r "[nvidia] " -b "Ignored :: " "skipping Nvidia actions"
        ;;
    h)
        # shellcheck disable=SC2034
        export flg_Shell=1
        print_log -r "[shell] " -b "Reevaluate :: " "shell options"
        ;;
    t) flg_DryRun=1 ;;
    m) flg_ThemeInstall=0 ;;
    x) 
        flg_NoSddm=0  # Allow SDDM installation if -x flag is used
        print_log -r "[sddm] " -b "Enabled :: " "SDDM will be installed"
        ;;
    *)
        cat <<EOF
Usage: $0 [options]
            i : [i]nstall hyprland without configs
            d : install hyprland [d]efaults without configs --noconfirm
            r : [r]estore config files
            s : enable system [s]ervices
            n : ignore/[n]o [n]vidia actions (-irsn to ignore nvidia)
            h : re-evaluate S[h]ell
            m : no the[m]e reinstallations
            t : [t]est run without executing (-irst to dry run all)
            x : enable SDDM installation (disabled by default)

NOTE:
        running without args is equivalent to -irs
        to ignore nvidia, run -irsn
        SDDM is disabled by default, use -x to enable

WRONG:
        install.sh -n # This will not work

EOF
        exit 1
        ;;
    esac
done

# Only export that are used outside this script
HYDE_LOG="$(date +'%y%m%d_%Hh%Mm%Ss')"
export flg_DryRun flg_Nvidia flg_Shell flg_Install flg_ThemeInstall flg_NoSddm HYDE_LOG

# Print SDDM status
if [ "${flg_NoSddm}" -eq 1 ]; then
    print_log -r "[sddm] " -b "Disabled :: " "SDDM installation and configuration skipped"
fi

if [ "${flg_DryRun}" -eq 1 ]; then
    print_log -n "[test-run] " -b "enabled :: " "Testing without executing"
elif [ $OPTIND -eq 1 ]; then
    flg_Install=1
    flg_Restore=1
    flg_Service=1
fi

#--------------------#
# pre-install script #
#--------------------#
if [ ${flg_Install} -eq 1 ] && [ ${flg_Restore} -eq 1 ]; then
    cat <<"EOF"
                _         _       _ _
 ___ ___ ___   |_|___ ___| |_ ___| | |
| . |  _| -_|  | |   |_ -|  _| .'| | |
|  _|_| |___|  |_|_|_|___|_| |__,|_|_|
|_|

EOF

    "${scrDir}/install_pre.sh"
fi

#------------#
# installing #
#------------#
if [ ${flg_Install} -eq 1 ]; then
    cat <<"EOF"

 _         _       _ _ _
|_|___ ___| |_ ___| | |_|___ ___
| |   |_ -|  _| .'| | | |   | . |
|_|_|_|___|_| |__,|_|_|_|_|_|_  |
                            |___|

EOF

    #----------------------#
    # prepare package list #
    #----------------------#
    shift $((OPTIND - 1))
    custom_pkg=$1
    cp "${scrDir}/pkg_core.lst" "${scrDir}/install_pkg.lst"
    trap 'mv "${scrDir}/install_pkg.lst" "${cacheDir}/logs/${HYDE_LOG}/install_pkg.lst"' EXIT

    # Remove SDDM from package list if flg_NoSddm is set
    if [ "${flg_NoSddm}" -eq 1 ]; then
        print_log -r "[sddm] " -b "Removing :: " "SDDM from package list"
        sed -i '/^sddm$/d' "${scrDir}/install_pkg.lst" 2>/dev/null || true
        sed -i '/^sddm-kcm$/d' "${scrDir}/install_pkg.lst" 2>/dev/null || true
        sed -i '/sddm/d' "${scrDir}/install_pkg.lst" 2>/dev/null || true
    fi

    echo -e "\n#user packages" >>"${scrDir}/install_pkg.lst" # Add a marker for user packages
    if [ -f "${custom_pkg}" ] && [ -n "${custom_pkg}" ]; then
        cat "${custom_pkg}" >>"${scrDir}/install_pkg.lst"
    fi

    #--------------------------------#
    # add nvidia drivers to the list #
    #--------------------------------#
    if nvidia_detect; then
        if [ ${flg_Nvidia} -eq 1 ]; then
            cat /usr/lib/modules/*/pkgbase | while read -r kernel; do
                echo "${kernel}-headers" >>"${scrDir}/install_pkg.lst"
            done
            nvidia_detect --drivers >>"${scrDir}/install_pkg.lst"
        else
            print_log -warn "Nvidia" "Nvidia GPU detected but ignored..."
        fi
    fi
    nvidia_detect --verbose

    #----------------#
    # get user prefs #
    #----------------#
    echo ""
    if ! chk_list "aurhlpr" "${aurList[@]}"; then
        print_log -c "\nAUR Helpers :: "
        aurList+=("yay-bin" "paru-bin") # Add this here instead of in global_fn.sh
        for i in "${!aurList[@]}"; do
            print_log -sec "$((i + 1))" " ${aurList[$i]} "
        done

        prompt_timer 120 "Enter option number [default: yay-bin] | q to quit "

        case "${PROMPT_INPUT}" in
        1) export getAur="yay" ;;
        2) export getAur="paru" ;;
        3) export getAur="yay-bin" ;;
        4) export getAur="paru-bin" ;;
        q)
            print_log -sec "AUR" -crit "Quit" "Exiting..."
            exit 1
            ;;
        *)
            print_log -sec "AUR" -warn "Defaulting to yay-bin"
            print_log -sec "AUR" -stat "default" "yay-bin"
            export getAur="yay-bin"
            ;;
        esac
        if [[ -z "$getAur" ]]; then
            print_log -sec "AUR" -crit "No AUR helper found..." "Log file at ${cacheDir}/logs/${HYDE_LOG}"
            exit 1
        fi
    fi

    if ! chk_list "myShell" "${shlList[@]}"; then
        print_log -c "Shell :: "
        for i in "${!shlList[@]}"; do
            print_log -sec "$((i + 1))" " ${shlList[$i]} "
        done
        prompt_timer 120 "Enter option number [default: zsh] | q to quit "

        case "${PROMPT_INPUT}" in
        1) export myShell="zsh" ;;
        2) export myShell="fish" ;;
        q)
            print_log -sec "shell" -crit "Quit" "Exiting..."
            exit 1
            ;;
        *)
            print_log -sec "shell" -warn "Defaulting to zsh"
            export myShell="zsh"
            ;;
        esac
        print_log -sec "shell" -stat "Added as shell" "${myShell}"
        echo "${myShell}" >>"${scrDir}/install_pkg.lst"

        if [[ -z "$myShell" ]]; then
            print_log -sec "shell" -crit "No shell found..." "Log file at ${cacheDir}/logs/${HYDE_LOG}"
            exit 1
        else
            print_log -sec "shell" -stat "detected :: " "${myShell}"
        fi
    fi

    if ! grep -q "^#user packages" "${scrDir}/install_pkg.lst"; then
        print_log -sec "pkg" -crit "No user packages found..." "Log file at ${cacheDir}/logs/${HYDE_LOG}/install.sh"
        exit 1
    fi

    #--------------------------------#
    # install packages from the list #
    #--------------------------------#
    "${scrDir}/install_pkg.sh" "${scrDir}/install_pkg.lst"
fi

#---------------------------#
# restore my custom configs #
#---------------------------#
if [ ${flg_Restore} -eq 1 ]; then
    cat <<"EOF"

             _           _
 ___ ___ ___| |_ ___ ___|_|___ ___
|  _| -_|_ -|  _| . |  _| |   | . |
|_| |___|___|_| |___|_| |_|_|_|_  |
                              |___|

EOF

    if [ "${flg_DryRun}" -ne 1 ] && [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
        hyprctl keyword misc:disable_autoreload 1 -q
    fi

    "${scrDir}/restore_fnt.sh"
    "${scrDir}/restore_cfg.sh"
    
    # Skip SDDM theme restoration if SDDM is disabled
    if [ "${flg_NoSddm}" -eq 0 ]; then
        "${scrDir}/restore_thm.sh"
    else
        # Run theme restoration but skip SDDM-related parts
        print_log -r "[sddm] " -b "Skipping :: " "SDDM theme restoration"
        SKIP_SDDM=1 "${scrDir}/restore_thm.sh"
    fi
    
    print_log -g "[generate] " "cache ::" "Wallpapers..."
    if [ "${flg_DryRun}" -ne 1 ]; then
        export PATH="$HOME/.local/lib/hyde:$HOME/.local/bin:${PATH}"
        "$HOME/.local/lib/hyde/swwwallcache.sh" -t ""
        "$HOME/.local/lib/hyde/theme.switch.sh" -q || true
        "$HOME/.local/lib/hyde/waybar.py" --update || true
        echo "[install] reload :: Hyprland"
    fi

fi

#---------------------#
# post-install script #
#---------------------#
if [ ${flg_Install} -eq 1 ] && [ ${flg_Restore} -eq 1 ]; then
    cat <<"EOF"

             _      _         _       _ _
 ___ ___ ___| |_   |_|___ ___| |_ ___| | |
| . | . |_ -|  _|  | |   |_ -|  _| .'| | |
|  _|___|___|_|    |_|_|_|___|_| |__,|_|_|
|_|

EOF

    "${scrDir}/install_pst.sh"
fi


#---------------------------#
# run migrations            #
#---------------------------#
if [ ${flg_Restore} -eq 1 ]; then

# migrationDir="$(realpath "$(dirname "$(realpath "$0")")/../migrations")"
migrationDir="${scrDir}/migrations"

if [ ! -d "${migrationDir}" ]; then
    print_log -warn "Migrations" "Directory not found: ${migrationDir}"
fi

echo "Running migrations from: ${migrationDir}"

if [ -d "${migrationDir}" ] && find "${migrationDir}" -type f | grep -q .; then
    migrationFile=$(find "${migrationDir}" -maxdepth 1 -type f -printf '%f\n' | sort -r | head -n 1)

    if [[ -n "${migrationFile}" && -f "${migrationDir}/${migrationFile}" ]]; then
        echo "Found migration file: ${migrationFile}"
        sh "${migrationDir}/${migrationFile}"
    else
        echo "No migration file found in ${migrationDir}. Skipping migrations."
    fi
fi

fi

#------------------------#
# enable system services #
#------------------------#
if [ ${flg_Service} -eq 1 ]; then
    cat <<"EOF"

                 _
 ___ ___ ___ _ _|_|___ ___ ___
|_ -| -_|  _| | | |  _| -_|_ -|
|___|___|_|  \_/|_|___|___|___|

EOF

    # Pass the SDDM flag to service restoration script
    if [ "${flg_NoSddm}" -eq 1 ]; then
        SKIP_SDDM=1 "${scrDir}/restore_svc.sh"
        
        # Setup automatic Hyprland startup via systemd
        print_log -g "[systemd] " "Setting up :: " "Automatic Hyprland startup"
        
        if [ "${flg_DryRun}" -ne 1 ]; then
            # Create user systemd directory if it doesn't exist
            mkdir -p ~/.config/systemd/user
            
            # Create Hyprland systemd service
            cat > ~/.config/systemd/user/hyprland.service << 'EOF'
[Unit]
Description=Hyprland Compositor
After=graphical-session.target
Wants=graphical-session.target
BindsTo=graphical-session.target

[Service]
Type=notify
ExecStart=/usr/bin/Hyprland
Restart=on-failure
RestartSec=1
TimeoutStopSec=10
KillMode=mixed
Environment=XDG_CURRENT_DESKTOP=Hyprland
Environment=XDG_SESSION_DESKTOP=Hyprland
Environment=XDG_SESSION_TYPE=wayland

[Install]
WantedBy=default.target
EOF

            # Enable auto-login for current user
            print_log -g "[systemd] " "Configuring :: " "Automatic login for user: ${USER}"
            
            # Create override directory for getty@tty1
            sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
            
            # Create auto-login override
            sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin ${USER} %I \$TERM
EOF

            # Create user login script that starts Hyprland
            cat > ~/.bash_profile << 'EOF'
# Auto-start Hyprland if logging in on tty1 and no display server is running
if [[ -z $DISPLAY && $XDG_VTNR -eq 1 && -z $WAYLAND_DISPLAY ]]; then
    # Start Hyprland
    exec Hyprland
fi
EOF

            # Add shell-specific profile configurations
            case "${myShell:-bash}" in
                "zsh")
                    cat > ~/.zprofile << 'EOF'
# Auto-start Hyprland if logging in on tty1 and no display server is running
if [[ -z $DISPLAY && $XDG_VTNR -eq 1 && -z $WAYLAND_DISPLAY ]]; then
    # Start Hyprland
    exec Hyprland
fi
EOF
                    ;;
                "fish")
                    # Create fish config directory if it doesn't exist
                    mkdir -p ~/.config/fish
                    cat > ~/.config/fish/config.fish << 'EOF'
# Auto-start Hyprland if logging in on tty1 and no display server is running
if test -z "$DISPLAY" -a "$XDG_VTNR" = "1" -a -z "$WAYLAND_DISPLAY"
    # Start Hyprland
    exec Hyprland
end
EOF
                    ;;
            esac

            # Enable and start the user systemd service (for future logins)
            systemctl --user daemon-reload
            systemctl --user enable hyprland.service
            
            # Reload systemd daemon for getty changes
            sudo systemctl daemon-reload
            
            print_log -g "[systemd] " "Configured :: " "Auto-login and Hyprland startup"
        else
            print_log -n "[test-run] " "Would create :: " "Hyprland systemd service and auto-login"
        fi
    else
        "${scrDir}/restore_svc.sh"
    fi
fi

if [ $flg_Install -eq 1 ]; then
    echo ""
    print_log -g "Installation" " :: " "COMPLETED!"
    if [ "${flg_NoSddm}" -eq 1 ]; then
        print_log -warn "SDDM" "SDDM was not installed. Hyprland will start automatically on boot."
        print_log -g "Auto-login" "Configured automatic login and Hyprland startup for user: ${USER}"
        print_log -g "Auto-login" "Hyprland will launch automatically when you boot into tty1"
        print_log -warn "Note" "If you need to access a terminal without starting Hyprland, switch to tty2-6 (Ctrl+Alt+F2-F6)"
    fi
fi
print_log -b "Log" " :: " -y "View logs at ${cacheDir}/logs/${HYDE_LOG}"
if [ $flg_Install -eq 1 ] ||
    [ $flg_Restore -eq 1 ] ||
    [ $flg_Service -eq 1 ] &&
    [ $flg_DryRun -ne 1 ]; then

    if [[ -z "${HYPRLAND_CONFIG:-}" ]] || [[ ! -f "${HYPRLAND_CONFIG}" ]]; then
        print_log -warn "Hyprland config not found! Might be a new install or upgrade."
        print_log -warn "Please reboot the system to apply new changes."
    fi

    print_log -stat "HyDE" "It is not recommended to use newly installed or upgraded HyDE without rebooting the system. Do you want to reboot the system? (y/N)"
    read -r answer

    if [[ "$answer" == [Yy] ]]; then
        echo "Rebooting system"
        systemctl reboot
    else
        echo "The system will not reboot"
    fi
fi
