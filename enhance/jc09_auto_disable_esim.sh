#!/bin/bash
#
# jc09 0727版本，模拟网页禁用esim，自动切卡
#
# 使用说明：
# 1. 通过adb把脚本放在/home/root目录： adb push jc09_auto_disable_esim.sh /home/root/
# 2. adb shell 后添加执行权限： chmod +x /home/root/jc09_auto_disable_esim.sh
# 3. 修改hostname.sh： vi /etc/init.d/hostname.sh
# 4. 在尾行添加以下命令并保存： bash /home/root/jc09_auto_disable_esim.sh > /home/root/.jc09_auto.log 2>&1 &
# 注：
# 1. 脚本执行日志在 /home/root/.jc09_auto.log
# 2. 可以适当修改参数来符合你的需求
# 3. 重启后不要网页登录后台，在没修改配置情况下，执行总时间为大约为 2分钟左右
#
# Copyright © 2023, oneisall8955, Co,. Ltd. All Rights Reserved.
# author：酷安@酷酷的liam

version="v6"
api_prefix="http://127.0.0.1:80"
# 执行禁用esim的模式，有限次数模式（limit_count_type）还是无限次数 unlimited_type
# 无限模式会强制必须切换成功，切换不成功会死循环一直重试
disable_esim_exec_type="limit_count_type"
# 执行禁用esim最大重试次数，disable_esim_exec_type="limit_count_type" 时有效
disable_esim_onetime_retry_max_count=50
# 守护多久，单位为分钟，这个时间段内不要登录后台，因为不能多设备登录，会踢出已存在的设备
# 不能小于1，小于1会自动强制设置为1
watchdog_duration_min=1
# 启动后等待秒数
# 不能小于1，小于1会自动强制设置为30
wait_seconds=30
#登录后台账号密码
username="admin"
password="admin"

function global_config_check_init() {
  echo "执行 global_config_check_init，对全局参数校验或初始化"
  if [[ "$disable_esim_exec_type" != "limit_count_type" && "$disable_esim_exec_type" != "unlimited_type" ]]; then
    echo "disable_esim_exec_type=$disable_esim_exec_type 设置不正确，强制设置为limit_count_type"
    disable_esim_exec_type="limit_count_type"
  fi
  if [[ $disable_esim_onetime_retry_max_count -lt 1 ]]; then
    echo "disable_esim_onetime_retry_max_count=$disable_esim_onetime_retry_max_count 设置不正确，强制设置为50"
    disable_esim_onetime_retry_max_count=50
  fi
  if [[ $watchdog_duration_min -lt 1 ]]; then
    echo "watchdog_duration_min=$watchdog_duration_min 设置不正确，强制设置为1"
    watchdog_duration_min=1
  fi

  out_wait_seconds=${out_wait_seconds:-"0"}
  out_wait_seconds=$((out_wait_seconds))
  if [[ $out_wait_seconds -gt 0 ]]; then
    wait_seconds=$out_wait_seconds
  fi
  if [[ $wait_seconds -lt 1 ]]; then
    echo "wait_seconds=$wait_seconds 设置不正确，强制设置为30"
    wait_seconds=30
  fi
  echo ""
}

function init_disable_esim_var() {
  login_count=0
  retry_count=0
  token=""
  issim0=""
  esim_enable=""
  #esim_enable0_state=""
  dual_esim_set1_state=""
  sim_status_cn="未知"
  change_network_5G4G3G_state=""
  net_type=""
  net_type_cn="未知"
}

function wait_thttpd() {
  echo "执行wait_thttpd，等待thttpd启动"
  thttpd=""
  while [[ -z "$thttpd" ]]; do
    # shellcheck disable=SC2009
    thttpd=$(ps | grep /usr/sbin/thttpd)
    if [[ -z "$thttpd" ]]; then
      echo "thttpd进程不存在，休眠1s"
      sleep 1
    fi
  done
  echo "thttpd进程已启动"
  echo "thttpd=[$thttpd]"
  echo ""
}

function login() {
  echo "执行login，模拟登录"
  login_response=""
  token=""
  # jsonp1693914184115("<blog>   <loginKey>f6fdffe48c908deb0f4c3bd36c032e72</loginKey>   <token>1P8nGUpu9GsfbwSDmXSjLlqu4mhdYuSX</token></blog>")
  login_response=$(curl -s --max-time 10 "$api_prefix/adminLogin?loginparam=%7B%22username%22%3A%22$username%22%2C%22password%22%3A%22$password%22%7D")
  token=$(echo "$login_response" | grep -oE '<token>([^<]+)</token>' | sed -e 's/<token>//;s/<\/token>//' | sed 's/^\s*//;s/\s*$//')
  echo "login_response=[$login_response]"
  echo "token=[$token]"
  echo ""
}

function esim_status() {
  echo "执行esim_status，模拟ESIM页面，检查ESIM状态"
  esim_status_response=""
  issim0=""
  esim_enable=""
  sim_status_cn="未知"
  # jsonp1693914184116("<blog>   <issim0>1</issim0>   <esimEnable>0</esimEnable></blog>")
  esim_status_response=$(curl -s --max-time 10 "$api_prefix/jsonp_esim_status" --header "Cookie: token=$token")
  issim0=$(echo "$esim_status_response" | grep -oE '<issim0>([^<]+)</issim0>' | sed -e 's/<issim0>//;s/<\/issim0>//' | sed 's/^\s*//;s/\s*$//')
  esim_enable=$(echo "$esim_status_response" | grep -oE '<esimEnable>([^<]+)</esimEnable>' | sed -e 's/<esimEnable>//;s/<\/esimEnable>//' | sed 's/^\s*//;s/\s*$//')
  if [[ "$esim_enable" == "0" ]]; then
    sim_status_cn="使用sim"
  fi
  if [[ "$esim_enable" == "1" ]]; then
    sim_status_cn="使用esim"
  fi
  echo "esim_status_response=[$esim_status_response]"
  echo "issim0=[$issim0]"
  echo "esim_enable=[$esim_enable]"
  echo "sim_status_cn=[$sim_status_cn]"
  echo ""
}

function internetconn() {
  echo "执行internetconn，模拟基本设置页面，检查5G/4G/3G"
  internetconn_response=""
  net_type=""
  net_type_cn="未知"
  # jsonp1693998484109("<blog>   <isDataOpen>true</isDataOpen>   <isRoaming>false</isRoaming>   <issim>true</issim>   <netType>2</netType></blog>")
  internetconn_response=$(curl -s --max-time 10 "$api_prefix/jsonp_internetconn" --header "Cookie: token=$token")
  net_type=$(echo "$internetconn_response" | grep -oE '<netType>([^<]+)</netType>' | sed -e 's/<netType>//;s/<\/netType>//' | sed 's/^\s*//;s/\s*$//')
  if [[ "$net_type" == "0" ]]; then
    net_type_cn="5G/4G/3G"
  fi
  if [[ "$net_type" == "1" ]]; then
    net_type_cn="5G NSA/SA"
  fi
  if [[ "$net_type" == "2" ]]; then
    net_type_cn="5G SA only"
  fi
  if [[ "$net_type" == "3" ]]; then
    net_type_cn="4G/3G"
  fi
  if [[ "$net_type" == "4" ]]; then
    net_type_cn="4G only"
  fi
  echo "internetconn_response=[$internetconn_response]"
  echo "net_type=[$net_type]"
  echo "net_type_cn=[$net_type_cn]"
  echo ""
}

# function esim_enable0(){
#     # jsonp1693966098179({   "state" : 1})
#     esim_enable0_response=""
#     esim_enable0_state=""
#     esim_enable0_response=$(curl -s --max-time 10 "$api_prefix/esim_enable?esim_enable_param=%7B%22esimEnable%22%3A0%7D --header "Cookie: token=$token"")
#     esim_enable0_state=$(echo "$esim_enable0_response" | grep -o '"state"[[:space:]]*:[[:space:]]*[0-9]*' | sed -E 's/"state"[[:space:]]*:[[:space:]]*//')
#     echo "esim_enable0_response=$esim_enable0_response"
#     echo "esim_enable0_state=$esim_enable0_state"
#     echo ""
# }

function dual_esim_set1() {
  echo "执行dual_esim_set1，模拟Esim切换页面，设置5G"
  dual_esim_set1_response=""
  dual_esim_set1_state=""
  # jsonp1693966620048({   "state" : 1})
  dual_esim_set1_response=$(curl -s --max-time 10 "$api_prefix/jsonp_dual_esim_set?set_id=%7B%22simid%22%3A1%7D" --header "Cookie: token=$token")
  dual_esim_set1_state=$(echo "$dual_esim_set1_response" | grep -o '"state"[[:space:]]*:[[:space:]]*[0-9]*' | sed -E 's/"state"[[:space:]]*:[[:space:]]*//')
  echo "dual_esim_set1_response=[$dual_esim_set1_response]"
  echo "dual_esim_set1_state=[$dual_esim_set1_state]"
  echo ""
}

function change_network_5G4G3G() {
  echo "执行change_network_5G4G3G，模拟基本设置页面，设置5G/4G/3G"
  change_network_5G4G3G_response=""
  change_network_5G4G3G_state=""
  # jsonp1693974541695({   "state" : 1})
  change_network_5G4G3G_response=$(curl -s --max-time 10 "$api_prefix/changeNetwork?changeNetwork=%7B%22isdataopen%22%3A1%2C%22type%22%3A0%7D" --header "Cookie: token=$token")
  change_network_5G4G3G_state=$(echo "$change_network_5G4G3G_response" | grep -o '"state"[[:space:]]*:[[:space:]]*[0-9]*' | sed -E 's/"state"[[:space:]]*:[[:space:]]*//')
  echo "change_network_5G4G3G_response=[$change_network_5G4G3G_response]"
  echo "change_network_5G4G3G_state=[$change_network_5G4G3G_state]"
  echo ""
}

function start_disable_esim() {
  echo ">>>>>>>>>> start_disable_esim 开始"
  echo "执行start_disable_esim"

  init_disable_esim_var

  login_count=0
  retry_count=0

  while [[ "$esim_enable" != "0" ]]; do

    ((retry_count++))

    echo "start_disable_esim 当前次数=$retry_count"

    if [[ "$disable_esim_exec_type" == "limit_count_type" && $retry_count > $disable_esim_onetime_retry_max_count ]]; then
      echo "有限次数模式，已达最大重试次数，最大次数=$disable_esim_onetime_retry_max_count"
      break
    fi

    # 登录
    while [[ -z "$token" ]]; do
      ((login_count++))
      login
      if [[ -z "$token" ]]; then
        echo "登录失败，获取token为空，login_count=$login_count"
      fi
    done

    echo "登录成功，token=$token，login_count=$login_count"

    # ESIM页面，检查ESIM状态
    esim_status
    # 基本设置页面，检查5G/4G/3G
    internetconn

    if [[ "$esim_enable" == "0" && "$net_type" == "0" ]]; then
      echo "检测到esim已被关闭，并且基本设置中网络是5G/4G/3G，跳过切卡"
      break
    fi

    echo "!!!!!!!!!! start_disable_esim 检查到需要切卡，即将执行切卡！"
    # Esim切换页面，设置5G
    dual_esim_set1
    if [[ "$dual_esim_set1_state" != "1" ]]; then
      echo "Esim切换页面，设置5G失败，仍需继续重试，retry_count=$retry_count"
      continue
    fi

    sleep 1
    # 基本设置页面，设置5G/4G/3G
    change_network_5G4G3G
    if [[ "$change_network_5G4G3G_state" != "1" ]]; then
      echo "基本设置页面，设置5G/4G/3G失败，仍需继续重试，retry_count=$retry_count"
      continue
    fi

    # ESIM页面，检查ESIM状态
    sleep 1
    esim_status
    # 基本设置页面，检查5G/4G/3G
    internetconn

    if [[ "$esim_enable" != "0" || "$net_type" != "0" ]]; then
      echo "检测到esim禁用失败或基本设置中网络不是5G/4G/3G 仍需继续重试，retry_count=$retry_count"
      echo "esim_enable=$esim_enable"
      echo "net_type=$net_type"
    fi
  done

  echo "<<<<<<<<<< start_disable_esim 结束，当前 esim_enable=$esim_enable ，net_type=$net_type，sim状态=$sim_status_cn ，网络模式=$net_type_cn"
}

function watchdog_process() {

  watchdog_duration=$((60 * watchdog_duration_min))
  start_timestamp=$(date +%s)
  start_timestamp_str=$(date -d @"$start_timestamp" +'%Y-%m-%d %H:%M:%S')
  end_timestamp=$((start_timestamp + watchdog_duration))
  end_timestamp_str=$(date -d @"$end_timestamp" +'%Y-%m-%d %H:%M:%S')

  echo ">>>>>>>>>> watchdog_process 开始"
  echo "执行watchdog_process，守护一段时间，当前时间=$start_timestamp_str"
  echo "守护$watchdog_duration_min 分钟，预计守护进程在 $end_timestamp_str 结束"

  now_timestamp=$(date +%s)
  watchdog_count=0
  while [[ $now_timestamp < $end_timestamp ]]; do
    ((watchdog_count++))
    echo ""
    echo ">>>>>守护进程执行第 $watchdog_count 次开始"
    echo "当前时间=$(date +'%Y-%m-%d %H:%M:%S')，预计在 $end_timestamp_str 结束守护进程"
    start_disable_esim
    echo "<<<<<守护进程执行第 $watchdog_count 次已结束，当前时间=$(date +'%Y-%m-%d %H:%M:%S')，预计在 $end_timestamp_str 结束守护进程"
    echo ""
    echo "正在等待下一次，请稍后"
    sleep 5
    now_timestamp=$(date +%s)
  done

  echo "守护进程结束，共执行了 $watchdog_count 次检查，当前时间=$(date +'%Y-%m-%d %H:%M:%S')"
  echo "<<<<<<<<<< watchdog_process 结束"
}

function main() {
  echo "脚本开始，version=$version，当前时间=$(date +'%Y-%m-%d %H:%M:%S')"
  # 检查配置
  global_config_check_init
  # 等待thttpd进程
  wait_thttpd
  # 等待一段时间先
  if [[ $wait_seconds -gt 0 ]]; then
    echo "等待 $wait_seconds 秒"
    sleep $wait_seconds
  fi
  # 模拟禁用esim，会先查再禁用
  start_disable_esim
  # 来到此处，应该禁用成功过一次了
  # 因开机后不知名原因，虽然禁用了esim，可能又被开启了
  # 故守护一段时间，在此段时间内循环执行 start_disable_esim
  sleep 5
  watchdog_process
  echo "脚本结束，version=$version，当前时间=$(date +'%Y-%m-%d %H:%M:%S')"
}

main
