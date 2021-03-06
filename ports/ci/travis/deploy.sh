#!/bin/bash

# Webcamoid, webcam capture application.
# Copyright (C) 2017  Gonzalo Exequiel Pedone
#
# Webcamoid is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Webcamoid is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Webcamoid. If not, see <http://www.gnu.org/licenses/>.
#
# Web-Site: http://webcamoid.github.io/

if [ "${ARCH_ROOT_BUILD}" = 1 ]; then
    EXEC='sudo ./root.x86_64/bin/arch-chroot root.x86_64'
elif [ "${TRAVIS_OS_NAME}" = linux ] && [ -z "${ANDROID_BUILD}" ]; then
    if [ -z "${DAILY_BUILD}" ]; then
        EXEC="docker exec ${DOCKERSYS}"
    else
        EXEC="docker exec -e DAILY_BUILD=1 ${DOCKERSYS}"
    fi
fi

git clone https://github.com/webcamoid/DeployTools.git

DEPLOYSCRIPT=deployscript.sh
export PYTHONPATH=${TRAVIS_BUILD_DIR}/DeployTools

if [ "${ANDROID_BUILD}" = 1 ]; then
    export JAVA_HOME=$(readlink -f /usr/bin/java | sed 's:bin/java::')
    export ANDROID_HOME="${PWD}/build/android-sdk"
    export ANDROID_NDK="${PWD}/build/android-ndk"
    export ANDROID_NDK_HOME=${ANDROID_NDK}
    export ANDROID_NDK_HOST=linux-x86_64
    export ANDROID_NDK_PLATFORM=android-${ANDROID_PLATFORM}
    export ANDROID_NDK_ROOT=${ANDROID_NDK}
    export ANDROID_SDK_ROOT=${ANDROID_HOME}
    export PATH="${JAVA_HOME}/bin/java:${PATH}"
    export PATH="$PATH:${ANDROID_HOME}/tools:${ANDROID_HOME}/tools/bin"
    export PATH="${PATH}:${ANDROID_HOME}/platform-tools"
    export PATH="${PATH}:${ANDROID_HOME}/emulator"
    export PATH="${PATH}:${ANDROID_NDK}"
    export ORIG_PATH="${PATH}"
    export KEYSTORE_PATH="${PWD}/keystores/debug.keystore"
    nArchs=$(echo "${TARGET_ARCH}" | tr ':' ' ' | wc -w)
    lastArch=$(echo "${TARGET_ARCH}" | awk -F: '{print $NF}')

    cat << EOF > package_info_sdkbt.conf
[System]
sdkBuildToolsRevision = ${ANDROID_BUILD_TOOLS_VERSION}
EOF

    if [ "${nArchs}" = 1 ]; then
        export PATH="${PWD}/build/Qt/${QTVER_ANDROID}/android/bin:${PWD}/.local/bin:${ORIG_PATH}"
        export BUILD_PATH=${PWD}/build-${lastArch}

        python3 DeployTools/deploy.py \
            -d "${BUILD_PATH}/android-build" \
            -c "${BUILD_PATH}/package_info.conf" \
            -c "${BUILD_PATH}/package_info_android.conf" \
            -c "${PWD}/package_info_sdkbt.conf" \
            -o "${PWD}/webcamoid-packages/android"
    else
        mkdir -p "${PWD}/webcamoid-data"

        for arch_ in $(echo "${TARGET_ARCH}" | tr ":" "\n"); do
            export PATH="${PWD}/build/Qt/${QTVER_ANDROID}/android/bin:${PWD}/.local/bin:${ORIG_PATH}"
            export BUILD_PATH=${PWD}/build-${arch_}

            python3 DeployTools/deploy.py \
                -r \
                -d "${BUILD_PATH}/android-build" \
                -c "${BUILD_PATH}/package_info.conf" \
                -c "${BUILD_PATH}/package_info_android.conf" \
                -c "${PWD}/package_info_sdkbt.conf"
            cp -rf "${BUILD_PATH}/android-build"/* "${PWD}/webcamoid-data"
        done

        cat << EOF > package_info_hide_arch.conf
[Package]
targetArch = any
hideArch = true
EOF

        python3 DeployTools/deploy.py \
            -s \
            -d "${PWD}/webcamoid-data" \
            -c "${PWD}/build/package_info.conf" \
            -c "${PWD}/build/package_info_android.conf" \
            -c "${PWD}/package_info_sdkbt.conf" \
            -c "${PWD}/package_info_hide_arch.conf" \
            -o "${PWD}/webcamoid-packages/android"
    fi
elif [ "${ARCH_ROOT_BUILD}" = 1 ]; then
    sudo mount --bind root.x86_64 root.x86_64
    sudo mount --bind $HOME root.x86_64/$HOME

    if [ -z "${ARCH_ROOT_MINGW}" ]; then
        outputFolder=linux
        extraConfs=
    else
        outputFolder=windows
        cat << EOF > package_info_strip.conf
[System]
stripCmd = ${ARCH_ROOT_MINGW}-w64-mingw32-strip
EOF
        extraConfs="-c \"\${PWD}/build/package_info_windows.conf\" \
        -c \"\${PWD}/package_info_strip.conf\""
    fi

    cat << EOF > ${DEPLOYSCRIPT}
#!/bin/sh

cd $TRAVIS_BUILD_DIR
export LC_ALL=C
export HOME=$HOME
export PATH="\${PWD}/.local/bin:\$PATH"
export PYTHONPATH="\${PWD}/DeployTools"
export WINEPREFIX=/opt/.wine
export TRAVIS_BRANCH=$TRAVIS_BRANCH
EOF

    if [ ! -z "${DAILY_BUILD}" ]; then
        cat << EOF >> ${DEPLOYSCRIPT}
export DAILY_BUILD=1
EOF
    fi

    cat << EOF >> ${DEPLOYSCRIPT}
python DeployTools/deploy.py \
    -d "\${PWD}/webcamoid-data" \
    -c "\${PWD}/build/package_info.conf" \
    ${extraConfs} \
    -o "\${PWD}/webcamoid-packages/${outputFolder}"
EOF
    chmod +x ${DEPLOYSCRIPT}
    sudo cp -vf ${DEPLOYSCRIPT} root.x86_64/$HOME/

    ${EXEC} bash $HOME/${DEPLOYSCRIPT}
    sudo umount root.x86_64/$HOME
    sudo umount root.x86_64
elif [ "${TRAVIS_OS_NAME}" = linux ]; then
    cat << EOF > ${DEPLOYSCRIPT}
#!/bin/sh

export PATH="\$PWD/.local/bin:\$PATH"
export PYTHONPATH="\${PWD}/DeployTools"
export TRAVIS_BRANCH=${TRAVIS_BRANCH}
xvfb-run --auto-servernum python3 DeployTools/deploy.py \
    -d "\${PWD}/webcamoid-data" \
    -c "\${PWD}/build/package_info.conf" \
    -o "\${PWD}/webcamoid-packages/linux"
EOF

    chmod +x ${DEPLOYSCRIPT}

    ${EXEC} bash ${DEPLOYSCRIPT}
elif [ "${TRAVIS_OS_NAME}" = osx ]; then
    python3 DeployTools/deploy.py \
        -d "${PWD}/webcamoid-data" \
        -c "${PWD}/build/package_info.conf" \
        -o "${PWD}/webcamoid-packages/mac"
fi
