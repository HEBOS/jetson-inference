#!/bin/bash
#
# Copyright (c) 2019, NVIDIA CORPORATION. All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.
#

APP_TITLE="Hello AI World (jetson-inference)"
LOG="[jetson-inference] "
WGET_QUIET="--quiet"


#
# exit message for user
#
function exit_message()
{
	echo " "

	if [ $1 = 0 ]; then
		echo "$LOG installation complete, exiting with status code $1"
	else
		echo "$LOG errors encountered during installation, exiting with code $1"
	fi

	echo "$LOG to run this tool again, use the following commands:"
	echo " "
	echo "    $ cd <jetson-inference>/build"
	echo "    $ ./install-pytorch.sh"
	echo " "

	exit $1
}

#
# prompt user for retry
#
function retry_prompt()
{
	dialog --backtitle "$APP_TITLE" \
			  --title "Download Error" \
			  --colors \
			  --extra-button \
			  --extra-label "Next" \
			  --cancel-label "Quit" \
			  --ok-label "Retry" \
			  --yesno "\nFailed to download '$1' (error code=$2)\n\nWould you like to try downloading it again?\n\n\ZbNote:\Zn  if this error keeps occuring, see here:\n https://eLinux.org/Jetson_Zoo" 12 60

	local retry_status=$?
	clear

	WGET_QUIET="--verbose"

	if [ $retry_status = 1 ]; then
		echo "$LOG packages failed to download"
		exit_message 1
	elif [ $retry_status != 0 ]; then
		return 1
	fi

	return 0
}


#
# try to download a file from URL
#
function attempt_download_file()
{
	local filename=$1
	local URL=$2
	
	wget $WGET_QUIET --show-progress --progress=bar:force:noscroll --no-check-certificate $URL -O $filename
	
	local wget_status=$?

	if [ $wget_status != 0 ]; then
		echo "$LOG wget failed to download '$filename' (error code=$wget_status)"
		return $wget_status
	fi

	#mv $filename $OUTPUT_DIR
	return 0
}


#
# download a file from URL
#
function download_file()
{
	local filename=$1
	local URL=$2
	
	WGET_QUIET="--quiet"

	while true; do
		attempt_download_file $filename $URL

		local download_status=$?

		if [ $download_status = 0 ]; then
			return 0
		fi

		retry_prompt $filename $download_status
	
		local retry_status=$?

		if [ $retry_status != 0 ]; then
			return 1
		fi
	done
}


#
# download and install a pip wheel
#
function download_wheel()
{
	local filename=$2
	local URL=$3

	download_file $filename $URL

	local download_status=$?

	if [ $download_status != 0 ]; then
		echo "$LOG failed to download $filename"
		return 1
	fi

	$1 install $filename

	local install_status=$?

	if [ $install_status != 0 ]; then
		echo "$LOG failed to install $filename"
		echo "$LOG    -- command:     $1 install $filename"
		echo "$LOG    -- error code:  $install_status"
		return 1
	fi

	return 0
}

	
#
# check if a particular deb package is installed with dpkg-query
# arg $1 -> package name
# arg $2 -> variable name to output status to (e.g. HAS_PACKAGE=1)
#
function find_deb_package()
{
	local PKG_NAME=$1
	local HAS_PKG=`dpkg-query -W --showformat='${Status}\n' $PKG_NAME|grep "install ok installed"`

	if [ "$HAS_PKG" == "" ]; then
		echo "$LOG Checking for '$PKG_NAME' deb package...not installed"
		return 1
	else
		echo "$LOG Checking for '$PKG_NAME' deb package...installed"
		eval "$2=INSTALLED"
		return 0
	fi
}


#
# install a debian package if it isn't already installed
# arg $1 -> package name
# arg $2 -> variable name to output status to (e.g. FOUND_PACKAGE=INSTALLED)
#
function install_deb_package()
{
	local PKG_NAME=$1
	
	# check to see if the package is already installed
	find_deb_package $PKG_NAME $2

	local pkg_status=$?

	# if not, install the package
	if [ $pkg_status != 0 ]; then
		echo "$LOG Missing '$PKG_NAME' deb package...installing '$PKG_NAME' package."
		sudo apt-get --force-yes --yes install $PKG_NAME
	else
		return 0
	fi
	
	# verify that the package was installed
	find_deb_package $PKG_NAME $2
	
	local install_status=$?

	if [ $install_status != 0 ]; then
		echo "$LOG Failed to install '$PKG_NAME' deb package."
		exit_message 1
		#return 1
	else
		echo "$LOG Successfully installed '$PKG_NAME' deb package."
		return 0
	fi
}


#
# install PyTorch
#
function install_pytorch_v110_python27()
{
	echo "$LOG Downloading PyTorch v1.1.0 (Python 2.7)..."

	# install apt packages
	install_deb_package "python-pip" FOUND_PIP
	install_deb_package "qtbase5-dev" FOUND_QT5
	install_deb_package "libjpeg-dev" FOUND_JPEG
	install_deb_package "zlib1g-dev" FOUND_ZLIB

	# install pytorch wheel
	download_wheel pip "torch-1.2.0a0+8554416-cp27-cp27mu-linux_aarch64.whl" "https://nvidia.box.com/shared/static/8gcxrmcc6q4oc7xsoybk5wb26rkwugme.whl"
	
	local wheel_status=$?

	if [ $wheel_status != 0 ]; then
		echo "$LOG failed to install PyTorch v1.1.0 (Python 2.7)"
		return 1
	fi

	# build torchvision
	echo "$LOG cloning torchvision..."
	rm -r -f torchvision-27
	git clone -bv0.5.0 https://github.com/dusty-nv/vision torchvision-27
	cd torchvision-27
	echo "$LOG building torchvision for Python 3.6..."
	sudo python setup.py install
	cd ../

	return 0
}


function install_pytorch_v110_python36()
{
	echo "$LOG Downloading PyTorch v1.1.0 (Python 3.6)..."

	# install apt packages
	install_deb_package "python3-pip" FOUND_PIP3
	install_deb_package "qtbase5-dev" FOUND_QT5
	install_deb_package "libjpeg-dev" FOUND_JPEG
	install_deb_package "zlib1g-dev" FOUND_ZLIB

	# install pytorch wheel
	download_wheel pip3 "torch-1.2.0a0+8554416-cp36-cp36m-linux_aarch64.whl" "https://nvidia.box.com/shared/static/06vlvedmqpqstu1dym49fo7aapgfyyu9.whl"

	local wheel_status=$?

	if [ $wheel_status != 0 ]; then
		echo "$LOG failed to install PyTorch v1.1.0 (Python 3.6)"
		return 1
	fi

	# build torchvision
	echo "$LOG cloning torchvision..."
	rm -r -f torchvision-36
	git clone -bv0.5.0 https://github.com/dusty-nv/vision torchvision-36
	cd torchvision-36
	echo "$LOG building torchvision for Python 3.6..."
	sudo python3 setup.py install
	cd ../

	return 0
}


#
# check L4T version
#
function check_L4T_version()
{
	JETSON_L4T_STRING=$(head -n 1 /etc/nv_tegra_release)

	if [ -z $2 ]; then
		echo "$LOG reading L4T version from \"dpkg-query --show nvidia-l4t-core\""

		JETSON_L4T_STRING=$(dpkg-query --showformat='${Version}' --show nvidia-l4t-core)
		local JETSON_L4T_ARRAY=(${JETSON_L4T_STRING//./ })	

		#echo ${JETSON_L4T_ARRAY[@]}
		#echo ${#JETSON_L4T_ARRAY[@]}

		JETSON_L4T_RELEASE=${JETSON_L4T_ARRAY[0]}
		JETSON_L4T_REVISION=${JETSON_L4T_ARRAY[1]}
	else
		echo "$LOG reading L4T version from /etc/nv_tegra_release"

		JETSON_L4T_RELEASE=$(echo $JETSON_L4T_STRING | cut -f 2 -d ' ' | grep -Po '(?<=R)[^;]+')
		JETSON_L4T_REVISION=$(echo $JETSON_L4T_STRING | cut -f 2 -d ',' | grep -Po '(?<=REVISION: )[^;]+')
	fi

	JETSON_L4T_VERSION="$JETSON_L4T_RELEASE.$JETSON_L4T_REVISION"
	echo "$LOG Jetson BSP Version:  L4T R$JETSON_L4T_VERSION"

	if [ $JETSON_L4T_RELEASE -lt 32 ]; then
		dialog --backtitle "$APP_TITLE" \
		  --title "PyTorch Automated Install requires JetPack ≥4.2" \
		  --colors \
		  --msgbox "\nThis script to install PyTorch from pre-built binaries\nrequires \ZbJetPack 4.2 or newer\Zn (L4T R32.1 or newer).\n\nThe version of L4T on your system is:  \ZbL4T R${JETSON_L4T_VERSION}\Zn\n\nIf you wish to install PyTorch for training on Jetson,\nplease upgrade to JetPack 4.2 or newer, or see these\ninstructions to build PyTorch from source:\n\n          \Zbhttps://eLinux.org/Jetson_Zoo\Zn\n\nNote that PyTorch isn't required to build the repo,\njust for re-training networks onboard your Jetson.\nYou can proceed following Hello AI World without it,\nexcept for the parts on Transfer Learning with PyTorch." 20 60

		clear
		echo " "
		echo "[jetson-inference]  this script to install PyTorch from pre-built binaries"
		echo "                    requires JetPack 4.2 or newer (L4T R32.1 or newer).  "
		echo "                    the version of L4T on your system is:  L4T R${JETSON_L4T_VERSION}"
		echo " "
		echo "                    if you wish to install PyTorch for training on Jetson,"
		echo "                    please upgrade to JetPack 4.2 or newer, or see these"
		echo "                    instructions to build PyTorch from source:"
		echo " "
		echo "                        > https://eLinux.org/Jetson_Zoo"
		echo " "
		echo "                    note that PyTorch isn't required to build the repo,"
		echo "                    just for re-training networks onboard your Jetson."
		echo " "
		echo "                    you can proceed following Hello AI World without it,"
		echo "                    except for the parts on Transfer Learning with PyTorch."

		exit_message 1
	fi
}


# check for dialog package
install_deb_package "dialog" FOUND_DIALOG
echo "$LOG FOUND_DIALOG=$FOUND_DIALOG"

# use customized RC config
export DIALOGRC=./install-pytorch.rc

# check L4T version
check_L4T_version


#
# main menu
#
while true; do

	packages_selected=$(dialog --backtitle "$APP_TITLE" \
							  --title "PyTorch Installer (L4T R$JETSON_L4T_VERSION)" \
							  --cancel-label "Quit" \
							  --colors \
							  --checklist "If you want to train DNN models on your Jetson, this tool will download and install PyTorch.  Select the desired versions of pre-built packages below, or see \Zbhttp://eLinux.org/Jetson_Zoo\Zn for instructions to build from source. \n\nYou can skip this step and select Quit if you don't want to install PyTorch.\n\n\ZbKeys:\Zn\n  ↑↓ Navigate Menu\n  Space to Select \n  Enter to Continue\n\n\ZbPackages to Install:\Zn" 20 80 2 \
							  --output-fd 1 \
							  1 "PyTorch v1.1.0 for Python 2.7" off \
							  2 "PyTorch v1.1.0 for Python 3.6" off \
							 )

	package_selection_status=$?
	clear

	echo "$LOG Package selection status:  $package_selection_status"

	if [ $package_selection_status = 0 ]; then

		if [ -z "$packages_selected" ]; then
			echo "$LOG No packages were selected for download."
		else
			echo "$LOG Packages selected for download:  $packages_selected"
		
			for pkg in $packages_selected
			do
				if [ $pkg = 1 ]; then
					install_pytorch_v110_python27
				elif [ $pkg = 2 ]; then
					install_pytorch_v110_python36
				fi
			done
		fi

		exit_message 0
	else
		echo "$LOG Package selection cancelled."
		exit_message 0
	fi

	exit_message 0
done

