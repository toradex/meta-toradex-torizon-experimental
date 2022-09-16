FILESEXTRAPATHS:prepend := "${THISDIR}/${BPN}:"

SRC_URI:append = " \
    file://0001-dockerd-daemon-use-default-system-config-when-none-i.patch \
    file://0002-cli-config-support-default-system-config.patch \
    file://0003-dynbinary-use-go-cross-compiler.patch \
    file://0004-libnetwork-use-GO-instead-of-go.patch \
"

require docker-torizon.inc
