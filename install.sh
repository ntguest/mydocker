#!/bin/sh
set -e
error() { echo -e "\e[31m[error] $*\e[39m"; exit 1; }
if [[ $EUID != 0 ]]; then error This installer requires root privileges. Try again as \"root\" ... ; fi

if ! whiptail -v; then
  apt install whiptail -y
fi

if ! docker info > /dev/null 2>&1; then
  echo "This script uses docker, and it isn't running - please start docker and try again!"
  case $ARCH in
    "i386" | "i686")
        apt install -y docker.io
    ;;
    *)
        curl -fsSL get.docker.com | sh
    ;;
  esac
fi

curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
languages() {
msg="message_$langset[@]"; msg=("${!msg}")
for b in ${!message_en[@]} ; do if [[ ! ${msg[$b]} ]] ; then msg[$b]=${message_en[$b]}; fi; done
}

if [ $(locale -a | grep -c "ru") != 0 ]; then langset=$(whiptail --title "Select language" --menu "" 9 60 2 --notags --nocancel "en" "English" "ru" "Russian"  3>&1 1>&2 2>&3 ); else langset="en"; fi
message_en=("Select services to install" "Enter path to configuration files:" "Enter MySQL root password" "Enter MySQL database name" "Enter MySQL database username" "Enter MySQL database user password" "Select Tailscale role" "Client" "Router" "Enter Tailscale auth key" "You can create it at your Tailscale account or leave blank and login later in cli" "Enter Cloudflared tunnel token" "You can get it at your Cloudflare Zero Trust dashboard / Access/ Tunnels" "Enter Zigbee device port" "Check Zigbee2MQTT documentation" "Enter bus for UPS" "Use lsusb to get it" "Enter device for UPS" "Enter advertised routes" "Enter time zone")
message_ru=("Выберите устанавливаемые службы" "Введите путь к конфигурационным файлам" "Введите пароль MySQL root" "Введите имя базы данных" "Введите имя пользователя базы данных" "Введите пароль пользователя базы данных" "Выберите роль Tailscale" "Клиент" "Роутер" "Введите ключ авторизации" "Создать ключ можно в аккаунте Tailscale или оставить поле пустым и авторизоваться в консоли" "Ведите токен туннеля " "Узнать его можно в разделе Cloudflare Zero Trust dashboard / Access/ Tunnels" "Введите порт Zigbee устройства" "Следуйте документации Zigbee2MQTT" "Введите шину UPS" "Найти можно с помощью lsusb" "Введите устройство UPS" "Введите маршрутизируемые сети" "Введите временную зону")
languages
# info ${msg[3]};

ARCH=$(uname -m)
PRIMARY_INTERFACE=$(ip route | awk '/^default/ { print $5; exit }')
IP_ADDRESS=$(ip -4 addr show dev "${PRIMARY_INTERFACE}" | awk '/inet / { sub("/.*", "", $2); print $2 }')

#apt-get install -y iptables-persistent

#iptables --policy INPUT ACCEPT
#iptables -F

SERVICES=$(whiptail --title "${msg[0]}" --checklist "" 18 60 10 --notags --nocancel \
HA "Home Assistant container" ON \
FED "File Editor" ON \
ESP "ESPHome" ON \
MARIA "MariaDB" OFF \
DUPL "Duplicati" ON \
CLOUD "Cloudflared tunnel" ON \
MQTT "Mosquito broker" ON \
Z2M "Zigbee2MQTT" ON 3>&1 1>&2 2>&3)

DATA_SHARE=$(whiptail --title "${msg[1]}" --inputbox "" 10 60 --nocancel /home 3>&1 1>&2 2>&3)
TIMEZONE=$(whiptail --title "${msg[19]}" --inputbox "" 10 60 --nocancel Europe/Kiev 3>&1 1>&2 2>&3)






usermod -aG docker $USER

cd $DATA_SHARE
wget https://raw.githubusercontent.com/ntguest/mydocker/main/files/docker-compose.yml
echo "Installing ...."
#docker-compose up -d  > /dev/null 2>&1
docker-compose up -d

cd /home/data/mosquitto/config
wget https://raw.githubusercontent.com/ntguest/mydocker/main/files/mosquitto.conf
wget https://raw.githubusercontent.com/ntguest/mydocker/main/files/passwd
docker exec mosquitto mosquitto_passwd -U /mosquitto/config/passwd
docker restart mosquitto

#cd /home/data/zigbee2mqtt/data
#wget https://raw.githubusercontent.com/ntguest/mydocker/main/files/configuration.yaml
#docker restart zigbee2mqtt

while [ ! -f "$DATA_SHARE/data/homeassistant/configuration.yaml" ]; do sleep 2; done
apt install wget unzip -y
mkdir "$DATA_SHARE/data/homeassistant/custom_components"
mkdir "$DATA_SHARE/data/homeassistant/custom_components/hacs"
cd "$DATA_SHARE/data/homeassistant/custom_components"
wget "https://github.com/hacs/integration/releases/latest/download/hacs.zip"
unzip "$DATA_SHARE/data/homeassistant/custom_components/hacs.zip" -d "$DATA_SHARE/data/homeassistant/custom_components/hacs"
rm "$DATA_SHARE/data/homeassistant/custom_components/hacs.zip"
cat << EOF >> $DATA_SHARE/data/homeassistant/configuration.yaml
homeassistant:
  packages: !include_dir_named packages
EOF
mkdir $DATA_SHARE/data/homeassistant/packages > /dev/null 2>&1
cat << EOF >> $DATA_SHARE/data/homeassistant/packages/sysmon.yaml
sensor:
  - platform: systemmonitor
    scan_interval: 180
    resources:
    - type: memory_use_percent
  - platform: systemmonitor
    scan_interval: 600
    resources:
    - type: memory_use
    - type: memory_free
    - type: swap_use
    - type: swap_free
    - type: swap_use_percent
    - type: disk_free
    - type: disk_use
    - type: disk_use_percent
      arg: /
    - type: last_boot
  - platform: systemmonitor
    resources:
    - type: processor_use
    - type: processor_temperature
EOF
              
cat << EOF >> $DATA_SHARE/data/homeassistant/packages/panel_file_editor.yaml
panel_iframe:
  configurator:
    title: File editor
    icon: mdi:wrench
    url: http://$IP_ADDRESS:3218
    require_admin: true
EOF

cat << EOF >> $DATA_SHARE/data/file-editor/settings.conf
{
    "LISTENIP": "0.0.0.0",
    "PORT": 3218,
    "GIT": false,
    "BASEPATH": "/homeassistant",
    "ENFORCE_BASEPATH": false,
    "SSL_CERTIFICATE": null,
    "SSL_KEY": null,
    "IGNORE_SSL": false,
    "HASS_API": "http://127.0.0.1:8123/api/",
    "HASS_WS_API": null,
    "HASS_API_PASSWORD": null,
    "USERNAME": null,
    "PASSWORD": null,
    "ALLOWED_NETWORKS": [],
    "ALLOWED_DOMAINS": [],
    "BANNED_IPS": [],
    "BANLIMIT": 0,
    "IGNORE_PATTERN": [],
    "DIRSFIRST": false,
    "SESAME": null,
    "SESAME_TOTP_SECRET": null,
    "VERIFY_HOSTNAME": null,
    "ENV_PREFIX": "HC_",
    "NOTIFY_SERVICE": "persistent_notification.create"
}
EOF
#fed HASS_API_PASSWORD "long-lived access token"
docker restart file-editor

cat << EOF >> $DATA_SHARE/data/homeassistant/packages/panel_esphome.yaml
panel_iframe:
  esphome:
    title: ESPHome
    icon: mdi:chip
    url: http://$IP_ADDRESS:6052
    require_admin: true
EOF

cat << EOF >> $DATA_SHARE/data/homeassistant/packages/panel_duplicati.yaml
panel_iframe:
  duplicati:
    title: Duplicati
    icon: mdi:file-restore
    url: http://$IP_ADDRESS:8200
    require_admin: true
EOF

cat << EOF >> $DATA_SHARE/data/homeassistant/packages/panel_portainer.yaml
panel_iframe:
  portainer:
    title: Portainer
    icon: mdi:docker
    url: http://$IP_ADDRESS:9000
    require_admin: true
EOF




cat <<EOF >>/etc/apt/sources.list
deb http://deb.debian.org/debian bullseye-backports main contrib non-free

deb-src http://deb.debian.org/debian bullseye-backports main contrib non-free
EOF
apt-get update &>/dev/null
apt-get -t bullseye-backports install -y dbus-broker
systemctl enable dbus-broker.service &>/dev/null

apt-get -t bullseye-backports install -y bluez*

docker restart homeassistant
echo -e "Finished, reboot for changes to take affect
