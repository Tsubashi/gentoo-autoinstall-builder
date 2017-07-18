# Purpose
This script is meant to build an unattended install CD for gentoo. In operation, it...
1. downloads the latest install disk, portage snapshot, stage 3 tarball.
2. packages them all together into a single iso.
3. adds an auto-run script which installs to the system onto /dev/vda.

# Use
This script doesn't actually install gentoo. It generates an iso which should be capable of an unattended install. In order to build the image..
1. Clone the repo 
2. Ensure you have the following installed:
  - curl
  - GNU sed
  - sudo
  - mkisofs
3. Ensure you have internet connectivity (all required files are downloaded for you)
4. Ensure you have sudo permissions. The script will ask for your password when it requires root permissions.
4. Run the following command:

    ```./build.sh```

5. You should then see the following line:
    
    ```This script will trash the folder '/tmp/gentoo-install' if it exists, wiping any contents. Are you sure? Press any key in the next 15 seconds to continue...```

6. Press a key to continue. 
7. Enter your password when prompted to authorize the script to run as root (via sudo).
8. Relax. Your install CD will be finished soon
