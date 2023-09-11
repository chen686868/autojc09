# 温度控制

移除4G/5G传感器的温度控制，可能对机器有损伤
详见：https://blog.csdn.net/cornerstone1/article/details/123552128
核心思路是对 /etc/thermalSensorsConfig.xml 进行修改

## 先备份源文件

- adb shell
- mount -rw -o remount /
- cp /etc/thermalSensorsConfig.xml /etc/thermalSensorsConfig.xml.bak

# 复制项目的 thermalSensorsConfig.xml 到 jc09 的 /etc/thermalSensorsConfig.xml

- adb push thermalSensorsConfig.xml /etc/

# 把jc09的/etc/thermalSensorsConfig.xml权限减低，与原来的权限保持为-r--r--r--
- adb shell
- mount -rw -o remount /
- chmod -w /etc/thermalSensorsConfig.xml

# 重启jc09
- adb shell
- reboot