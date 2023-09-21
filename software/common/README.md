# 通用软件
- jq-linux-arm64
一个JQuery工具
```shell
adb push jq-linux-arm64 /home/root/jq
adb shell

mount -rw -o remount /
chmod +x /home/root/jq
ln -s /home/root/jq /usr/bin/jq
```
