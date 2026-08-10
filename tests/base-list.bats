#!/usr/bin/env bats
load helpers

@test "base.list parses: no comment lines, one token per line" {
  run bash -c "grep -vE '^\s*(#|\$)' '$REPO_ROOT/packages/base.list' | grep -nE '\s' || true"
  assert_output ""
}

@test "base.list contains the core packages + CachyOS identity" {
  for p in base sudo iptables-nft openssh git vim pacman \
           cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist \
           cachyos-hooks cachyos-settings cachyos-rate-mirrors \
           fish cachyos-fish-config zsh cachyos-zsh-config pacman-contrib pkgfile; do
    run bash -c "grep -vE '^\s*(#|\$)' '$REPO_ROOT/packages/base.list' | grep -qx '$p'"
    assert_success
  done
}

@test "base.list contains the CachyOS-default terminal packages" {
  for p in base-devel archlinux-keyring man-pages less diffutils e2fsprogs perl python \
           plocate pv lsb-release logrotate nano-syntax-highlighting micro cachyos-micro-settings \
           btop duf ripgrep fd inxi s-nail unzip unrar \
           wget rsync bind inetutils ufw ufw-extras reflector rebuild-detector cachy-update; do
    run bash -c "grep -vE '^\s*(#|\$)' '$REPO_ROOT/packages/base.list' | grep -qx '$p'"
    assert_success
  done
}

@test "base.list excludes packages that are not CachyOS defaults" {
  for p in paru downgrade nmap tcpdump mc net-tools \
           whois lftp lynx irssi wipe ttf-fira-code; do
    run bash -c "grep -vE '^\s*(#|\$)' '$REPO_ROOT/packages/base.list' | grep -qx '$p'"
    assert_failure
  done
}

@test "base.list contains the WSL-parity gap-fillers" {
  for p in tmux openbsd-netcat lsof; do
    run bash -c "grep -vE '^\s*(#|\$)' '$REPO_ROOT/packages/base.list' | grep -qx '$p'"
    assert_success
  done
}
