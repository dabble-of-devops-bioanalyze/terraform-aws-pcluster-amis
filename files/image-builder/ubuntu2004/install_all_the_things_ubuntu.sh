#!/usr/bin/env bash


export LOCAL_USER="ubuntu"
if ! command -v apt-get &> /dev/null
then
        echo "On OS Alinux2"
        export LOCAL_USER="ec2-user"
        exit 0
fi

export DISPLAY=:0
export DEBIAN_FRONTEND=noninteractive

export TASK="System"
echo "===================================================="
echo "# Starting: ${TASK}"
echo "===================================================="
apt-add-repository -y universe
apt-get update -y
apt-get install -y \
  software-properties-common \
  apt-transport-https \
  wget \
  lmod \
  tasksel \
  zlib1g-dev \
  lsof \
  git \
  build-essential

apt install -y --no-install-recommends software-properties-common dirmngr

apt-add-repository -y ppa:ansible/ansible
apt install -y ansible

export TASK="Nodejs"
echo "===================================================="
echo "# Starting: ${TASK}"
echo "===================================================="

FILE="nodesource_deb_setup.sh"
if [ -f "$FILE" ]; then
    echo "$FILE exists."
else
  curl -sL https://deb.nodesource.com/setup_14.x -o ./nodesource_deb_setup.sh
fi
bash ./nodesource_deb_setup.sh
apt install -y nodejs || echo "Unable to install nodejs"
npm install -g configurable-http-proxy

export TASK="Singularity"
echo "===================================================="
echo "# Starting: ${TASK}"
echo "===================================================="
apt-get install -y \
    build-essential \
    libssl-dev \
    uuid-dev \
    libgpgme11-dev \
    squashfs-tools \
    libseccomp-dev \
    wget \
    pkg-config \
    git

wget -O- http://neuro.debian.net/lists/focal.us-nh.full | sudo tee /etc/apt/sources.list.d/neurodebian.sources.list
apt-key adv --recv-keys --keyserver hkps://keyserver.ubuntu.com 0xA5D32F012649A5A9
apt-get update -y
apt-get install -y singularity-container

export TASK="R"
echo "===================================================="
echo "# Starting: ${TASK}"
echo "===================================================="

wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | sudo tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc
# add the R 4.0 repo from CRAN -- adjust 'focal' to 'groovy' or 'bionic' as needed
add-apt-repository -y "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/"
add-apt-repository -y ppa:c2d4u.team/c2d4u4.0+
apt-get update -y
apt install --no-install-recommends -y r-base
apt install -y --no-install-recommends r-cran-rstan
apt install -y --no-install-recommends r-cran-tidyverse

export TASK="RStudio"
echo "===================================================="
echo "# Starting: ${TASK}"
echo "===================================================="
FILE="rstudio-2022.12.0-353-amd64.deb"
if [ -f "$FILE" ]; then
    echo "$FILE exists."
else
  wget https://download1.rstudio.org/electron/bionic/amd64/rstudio-2022.12.0-353-amd64.deb
fi

apt install -y ./rstudio-2022.12.0-353-amd64.deb

export TASK="VSCode"
echo "===================================================="
echo "# Starting: ${TASK}"
echo "===================================================="
wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | sudo apt-key add -
add-apt-repository -y "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main"
apt-get update -y
apt install -y code

export TASK="OpenDemand Reqs"
echo "===================================================="
echo "# Starting: ${TASK}"
echo "===================================================="
FILE="turbovnc_3.0.2_amd64.deb"
if [ -f "$FILE" ]; then
    echo "$FILE exists."
else
  wget https://sourceforge.net/projects/turbovnc/files/3.0.2/turbovnc_3.0.2_amd64.deb/download -O turbovnc_3.0.2_amd64.deb
fi
apt install -y ./turbovnc_3.0.2_amd64.deb
# installs to /opt/TurboVNC/bin/

FILE="virtualgl_3.0.2_amd64.deb"
if [ -f "$FILE" ]; then
    echo "$FILE exists."
else
  wget https://sourceforge.net/projects/virtualgl/files/3.0.2/virtualgl_3.0.2_amd64.deb/download -O virtualgl_3.0.2_amd64.deb
fi
apt install -y ./virtualgl_3.0.2_amd64.deb

apt install -y snapd
snap install -y novnc
apt-get install -y websockify nmap

export TASK="Qt6"
echo "===================================================="
echo "# Starting: ${TASK}"
echo "===================================================="
add-apt-repository -y ppa:okirby/qt6-backports
apt update -y
apt install -y qt6-base-dev

export TASK="Qt5"
echo "===================================================="
echo "# Starting: ${TASK}"
echo "===================================================="
apt-get install -y \
  pyqt5-dev \
  pyqt5-dev-tools \
  libqt5x11extras5-dev

export TASK="Desktop"
echo "===================================================="
echo "# Starting: ${TASK}"
echo "===================================================="
env DEBIAN_FRONTEND=noninteractive apt-get install -y \
      dbus-x11 \
      procps \
      psmisc

env DEBIAN_FRONTEND=noninteractive apt-get install -y \
      xdg-utils \
      xdg-user-dirs \
      menu-xdg \
      mime-support \
      desktop-file-utils \
      bash-completion

env DEBIAN_FRONTEND=noninteractive apt-get install -y \
      mesa-utils-extra \
      libxv1 \
      sudo \
      lsb-release

env DEBIAN_FRONTEND=noninteractive apt-get install -y \
      ubuntu-mate-desktop^

env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    xfce4

exit 0
