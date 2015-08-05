#!/bin/bash
apt-get install\
  x11-xserver-utils\
  iceweasel\
  xdg-utils\
  libnotify-bin\
  xinit\
  dmenu\
  rxvt-unicode-256color
vcsh clone https://github.com/hgto/Xdots Xdots
vcsh Xdots reset --hard HEAD
echo "install sxhkd and bspwm yourself"
