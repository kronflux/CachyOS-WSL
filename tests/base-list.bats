#!/usr/bin/env bats
load helpers

@test "base.list parses: no comment lines, one token per line" {
  run bash -c "grep -vE '^\s*(#|\$)' '$REPO_ROOT/packages/base.list' | grep -nE '\s' || true"
  assert_output ""
}

@test "base.list keeps the P1 core + CachyOS identity" {
  for p in base sudo iptables-nft openssh git vim pacman \
           cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist \
           cachyos-hooks cachyos-settings cachyos-rate-mirrors \
           fish cachyos-fish-config zsh cachyos-zsh-config pacman-contrib pkgfile; do
    run bash -c "grep -vE '^\s*(#|\$)' '$REPO_ROOT/packages/base.list' | grep -qx '$p'"
    assert_success
  done
}

@test "base.list adds the Phase 2 parity packages" {
  for p in base-devel archlinux-keyring man-pages less diffutils e2fsprogs perl python \
           mlocate pv wipe paru reflector downgrade nano-syntax-highlighting mc tmux \
           inxi irssi lynx wget rsync nmap tcpdump bind-tools net-tools inetutils \
           gnu-netcat whois lftp ttf-fira-code; do
    run bash -c "grep -vE '^\s*(#|\$)' '$REPO_ROOT/packages/base.list' | grep -qx '$p'"
    assert_success
  done
}
