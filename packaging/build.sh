#!/usr/bin/env bash


# ##########################################################################################
#                       Archey 4 distribution packages building script                     #
#
# Dependencies :
# * python3
# * rpm
# * bsdtar
# * debsigs
# * fpm >= 1.14.0
# * twine >= 3.1.1
#
# Procedure to install them on Debian :
# $ sudo apt install ruby rpm build-essential libarchive-tools debsigs rubygems python3-pip
# $ sudo gem install --no-document fpm
# $ sudo pip3 install setuptools twine
#
# Run it as :
# $ bash packaging/build.sh [REVISION] [0xGPG_IDENTITY]
#
# If you happen to tweak packaging scripts, please lint them before submitting changes :
# $ shellcheck packaging/*
#
# ##########################################################################################


# Abort on error, don't allow usages of undeclared variable.
set -e ; set -u


# Let's gather some metadata from the `setup.py` file.
NAME="$(python3 setup.py --name)"
VERSION="$(python3 setup.py --version)"
AUTHOR="$(python3 setup.py --author)"
AUTHOR_EMAIL="$(python3 setup.py --author-email)"
SUPPORTED_PYTHON_VERSIONS="$(python3 setup.py --classifiers | grep 'Programming Language' | grep -Po '\d+\.\d+')"


# DRY.
REVISION="${1:-1}"
ARCHITECTURE='all'
GPG_IDENTITY="${2:-}"
DIST_OUTPUT='./dist'
FPM_COMMON_ARGS=(
	--input-type python \
	--force \
	--log error \
	--vendor "" \
	--iteration "$REVISION" \
	--category 'utils' \
	--provides 'archey' \
	--provides 'archey4' \
	--config-files "etc/archey4/" \
	--config-files "etc/archey4/config.json" \
	--architecture "$ARCHITECTURE" \
	--maintainer "${AUTHOR} <${AUTHOR_EMAIL}>" \
	--after-install ./packaging/after_install \
	--after-upgrade ./packaging/after_install \
	--after-remove ./packaging/after_remove \
	--before-remove ./packaging/before_remove \
	--python-bin python3 \
	--python-install-bin 'usr/bin/' \
	--python-install-data 'usr/' \
	--no-python-fix-name \
	--no-python-dependencies \
)


echo ">>> Packages generation for ${NAME}_v${VERSION}-${REVISION} <<<"


# Prepare the configuration file under a regular `etc/` directory.
mkdir -p etc/archey4/ && \
	cp config.json etc/archey4/config.json
# Prepare the AppArmor profile (without `abi` directive, unsupported by Debian).
mkdir -p etc/apparmor.d/ && \
	sed '/^abi.*,$/d' apparmor.profile > etc/apparmor.d/usr.bin.archey4
# Prepare and compress the manual page.
sed -e "s/\${DATE}/$(date +'%B %Y')/1" -e "s/\${VERSION}/${VERSION}/1" archey.1 | \
	gzip -c --best - > "${DIST_OUTPUT}/archey.1.gz"
# Clean any previous Setuptools build output.
python3 setup.py -q clean --all 2> /dev/null


# Prevent Setuptools from generating byte-code files.
# Important note :
#   It allows the packager to build generic distribution packages without shipping byte-code related to its Python interpreter version.
#   A noticeable side-effect may be the appearance of "untracked" byte-code files (when running Archey as root for instance).
#   Check `packaging/before_remove` script to see how Archey deals with them.
export PYTHONDONTWRITEBYTECODE=1


# Build a Debian (.DEB) package.
echo 'Now generating Debian package...'
fpm \
	"${FPM_COMMON_ARGS[@]}" \
	--config-files "etc/apparmor.d/" \
	--config-files "etc/apparmor.d/usr.bin.archey4" \
	--output-type deb \
	--package "${DIST_OUTPUT}/${NAME}_${VERSION}-${REVISION}_${ARCHITECTURE}.deb" \
	--depends 'python3 >= 3.6' \
	--depends 'python3-distro' \
	--depends 'python3-netifaces' \
	--python-install-lib 'usr/lib/python3/dist-packages/' \
	--deb-priority 'optional' \
	--deb-field 'Recommends: procps' \
	--deb-field 'Suggests: apparmor, dnsutils, lm-sensors, pciutils, virt-what, wmctrl' \
	--deb-no-default-config-files \
	setup.py

# Sign the resulting Debian package if a GPG identity has been provided.
if [ -n "$GPG_IDENTITY" ]; then
	echo "Now signing Debian package with ${GPG_IDENTITY}..."
	debsigs \
		--sign=origin \
		-k "$GPG_IDENTITY" \
		"${DIST_OUTPUT}/${NAME}_${VERSION}-${REVISION}_${ARCHITECTURE}.deb"
fi


# Build Red Hat / CentOS / Fedora (.RPM) packages.
for python_version in $SUPPORTED_PYTHON_VERSIONS; do
	echo "Now generating RPM package (Python ${python_version})..."
	fpm \
		"${FPM_COMMON_ARGS[@]}" \
		--output-type rpm \
		--package "${DIST_OUTPUT}/${NAME}-${VERSION}-${REVISION}.py${python_version//.}.noarch.rpm" \
		--depends "python3 >= ${python_version}" \
		--depends 'python3-distro' \
		--depends 'python3-netifaces' \
		--python-install-lib "usr/lib/python${python_version}/site-packages/" \
		setup.py
done


## -----------------------------------------------------------------------------------
## v4.7.2+ : Arch Linux package proposed as GitHub assets will now be built from AUR.
## See <https://aur.archlinux.org/packages/archey4/>.
## -----------------------------------------------------------------------------------
# # Build an Arch Linux (.TAR.XZ) package.
# PYTHON_VERSION='3.9'  # See <https://www.archlinux.org/packages/extra/x86_64/python/>.
# echo "Now generating Arch Linux package (Python ${PYTHON_VERSION})..."
# fpm \
# 	"${FPM_COMMON_ARGS[@]}" \
# 	--output-type pacman \
# 	--package "${DIST_OUTPUT}/${NAME}-${VERSION}-${REVISION}-any.pkg.tar.xz" \
# 	--depends "python>=${PYTHON_VERSION}" \
# 	--depends 'python-distro' \
# 	--depends 'python-netifaces' \
# 	--conflicts 'archey-git' \
# 	--conflicts 'archey2' \
# 	--conflicts 'archey3-git' \
# 	--conflicts 'pyarchey' \
# 	--python-install-lib "usr/lib/python${PYTHON_VERSION}/site-packages/" \
# 	--pacman-optional-depends 'bind-tools: WAN_IP would be detected faster' \
# 	--pacman-optional-depends 'lm_sensors: Temperature would be more accurate' \
# 	--pacman-optional-depends 'pciutils: GPU wouldn'"'"'t be detected without it' \
# 	--pacman-optional-depends 'procps-ng: Many entries wouldn'"'"'t work without it' \
# 	--pacman-optional-depends 'virt-what: Model would contain details about the hypervisor' \
# 	--pacman-optional-depends 'wmctrl: WindowManager would be more accurate' \
# 	setup.py


# Remove the fake `etc/archey4/` & `etc/apparmor.d/` trees.
rm etc/archey4/config.json && \
	rmdir --ignore-fail-on-non-empty -p etc/archey4/
rm etc/apparmor.d/usr.bin.archey4 && \
	rmdir --ignore-fail-on-non-empty -p etc/apparmor.d/


# Silence some Setuptools warnings by re-enabling byte-code generation.
unset PYTHONDONTWRITEBYTECODE


# Build Python source TAR and WHEEL distribution packages.
echo 'Now building source TAR and WHEEL distribution packages...'
python3 setup.py -q sdist bdist_wheel

sdist_artefact="${DIST_OUTPUT}/${NAME}-${VERSION}.tar.gz"
wheel_artefact="${DIST_OUTPUT}/${NAME}-${VERSION}-py3-none-any.whl"

# Check whether packages description will render correctly on PyPI.
echo 'Now checking PyPI description rendering...'
if twine check "$sdist_artefact" "$wheel_artefact" && test -n "$GPG_IDENTITY" ; then
	echo -n 'Upload source and wheel distribution packages to PyPI ? [y/N] '
	read -r -n 1 -p '' && echo
	if [[ "$REPLY" =~ ^[yY]$ ]]; then
		echo 'Now signing & uploading source TAR and WHEEL to PyPI...'
		twine upload \
			--sign --identity "$GPG_IDENTITY" \
			"$sdist_artefact" "$wheel_artefact"
	fi
fi
