#! /bin/sh
sleep 3
if ping -c 4 www.google.ch > /dev/null 2>&1; then
  cd /root/common
  git fetch
  git merge
  cd /root/4.0
  git fetch
  git merge --autostash
  for i in {1..10}; do
    sudo make -j$(( $(nproc) - 1 )) image IMG_NAME=iso THREADS=$(( $(nproc) - 1 ));
    # Wait up to 30 seconds for ISO to appear
    timeout=30
    while [ $timeout -gt 0 ]; do
      if ls stage/*.iso 1>/dev/null 2>&1; then
        break
      fi
      sleep 1
      timeout=$((timeout - 1))
    done
    if sudo mv stage/*.iso /mnt/c/Users/dcaso/Downloads/Ph-Builds; then
      exit 0
    fi
  done
fi
