#!/bin/sh
set -e
error() { echo -e "\e[31m[error] $*\e[39m"; exit 1; }
if [[ $EUID != 0 ]]; then error This installer requires root privileges. Try again as \"root\" ... ; fi
apt install whiptail -y

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
MARIA "MariaDB" ON \
DUPL "Duplicati" ON \
CLOUD "Cloudflared tunnel" ON \
MQTT "Mosquito broker" ON \
Z2M "Zigbee2MQTT" OFF 3>&1 1>&2 2>&3)

DATA_SHARE=$(whiptail --title "${msg[1]}" --inputbox "" 10 60 --nocancel /home 3>&1 1>&2 2>&3)
TIMEZONE=$(whiptail --title "${msg[19]}" --inputbox "" 10 60 --nocancel Europe/Kiev 3>&1 1>&2 2>&3)

cat << EOF >> $DATA_SHARE/docker-compose.yml
version: '2'
services:
EOF

for word in $SERVICES
do
    if [ $word == "\"HA\"" ]; then
#      iptables -A INPUT -p tcp --dport 8123 -m state --state NEW -j ACCEPT
      cat << EOF >> $DATA_SHARE/docker-compose.yml
    home-assistant:
        container_name: homeassistant
        volumes:
            - '$DATA_SHARE/data/homeassistant:/config'
            - '/etc/localtime:/etc/localtime:ro'
            - '/var/run/docker.sock:/var/run/docker.sock'
            - /run/dbus:/run/dbus:ro
        devices:
            - /dev/ttyUSB0:/dev/ttyUSB0
        network_mode: host
        restart: always
        privileged: true
        image: 'homeassistant/home-assistant:stable'
EOF
    fi
done

for word in $SERVICES
do
    if [ $word == "\"FED\"" ]; then
#      iptables -A INPUT -p tcp --dport 3218 -m state --state NEW -j ACCEPT
      case $ARCH in
        "i386" | "i686")
            FED_IMAGE="mc303/hass-configurator"
        ;;
        *)
            FED_IMAGE="causticlab/hass-configurator-docker"
        ;;
      esac
      cat << EOF >> $DATA_SHARE/docker-compose.yml
    file-editor:
        container_name: file-editor
        network_mode: host
        ports:
            - '3218:3218'
        restart: always
        volumes:
            - '$DATA_SHARE/data/homeassistant:/homeassistant'
            - '$DATA_SHARE/data/esphome:/esphome'
            - '$DATA_SHARE/data/file-editor:/config'
        image: $FED_IMAGE
EOF
    fi
done

for word in $SERVICES
do
    if [ $word == "\"ESP\"" ]; then
#      iptables -A INPUT -p tcp --dport 6052 -m state --state NEW -j ACCEPT
      case $ARCH in
        "i386" | "i686")
        ;;
        *)
            cat << EOF >> $DATA_SHARE/docker-compose.yml
    esphome:
        container_name: esphome
        volumes:
            - '$DATA_SHARE/data/esphome:/config'
            - '/etc/localtime:/etc/localtime:ro'
        ports:
            - '6052:6052'
        network_mode: host
        restart: always
        image: esphome/esphome
EOF
        ;;
      esac
    fi
done

for word in $SERVICES
do
    if [ $word == "\"MARIA\"" ]; then
#      iptables -A INPUT -p tcp --dport 3308 -m state --state NEW -j ACCEPT
         SQL_RT_PWD=$(whiptail --title "${msg[2]}" --inputbox "" 10 60 --nocancel change_password 3>&1 1>&2 2>&3)
         SQL_DB=$(whiptail --title "${msg[3]}" --inputbox "" 10 60 --nocancel homeassistant_db 3>&1 1>&2 2>&3)
         SQL_USR=$(whiptail --title "${msg[4]}" --inputbox "" 10 60 --nocancel homeassistant 3>&1 1>&2 2>&3)
         SQL_PWD=$(whiptail --title "${msg[5]}" --inputbox "" 10 60 --nocancel change_password 3>&1 1>&2 2>&3)
    fi
done

#https://thesmarthomejourney.com/2022/04/04/home-assistant-docker-backup/
for word in $SERVICES
do
    if [ $word == "\"DUPL\"" ]; then
#      iptables -A INPUT -p tcp --dport 8200 -m state --state NEW -j ACCEPT
      cat << EOF >> $DATA_SHARE/docker-compose.yml
    duplicati:
        image: lscr.io/linuxserver/duplicati:latest
        container_name: duplicati
        environment:
            - PUID=0
            - PGID=1000
            - TZ=$TIMEZONE
        volumes:
            - $DATA_SHARE/data/duplicati/config:/config
            - $DATA_SHARE/backups:/backups
            - $DATA_SHARE/data:/source
        ports:
          - 8200:8200
        restart: unless-stopped
EOF
    fi
done

for word in $SERVICES
do
    if [ $word == "\"CLOUD\"" ]; then
      CLOUDTOKEN=$(whiptail --title "${msg[11]}" --inputbox "${msg[12]}" 10 60 --nocancel 3>&1 1>&2 2>&3)
      cat << EOF >> $DATA_SHARE/docker-compose.yml
    cloudflared:
        image: erisamoe/cloudflared
        container_name: cloudflared
        restart: unless-stopped
        command: tunnel run
        environment:
            - TUNNEL_TOKEN=${CLOUDTOKEN}
EOF
    fi
done

for word in $SERVICES
do
    if [ $word == "\"MQTT\"" ]; then
#      iptables -A INPUT -p tcp --dport 1883 -m state --state NEW -j ACCEPT
#      iptables -A INPUT -p tcp --dport 9001 -m state --state NEW -j ACCEPT
      cat << EOF >> $DATA_SHARE/docker-compose.yml
    mosquitto:
        container_name: mqtt
        image: eclipse-mosquitto
        volumes:
            - ./mosquitto_data/:/mosquitto/data/
        ports:
            - "1883:1883"
        restart: always
EOF
    fi
done

for word in $SERVICES
do
    if [ $word == "\"Z2M\"" ]; then
      Z2M_DEVICE=$(whiptail --title "${msg[13]}" --inputbox "${msg[14]}" 10 60 --nocancel /dev/ttyACM0 3>&1 1>&2 2>&3)
      case $ARCH in
        "i386" | "i686")
            Z2M_IMAGE="zigbee2mqtt/zigbee2mqtt-i386"
        ;;
        *)
            Z2M_IMAGE="koenkk/zigbee2mqtt"
        ;;
      esac
      cat << EOF >> $DATA_SHARE/docker-compose.yml
    zigbee2mqtt:
        container_name: zigbee2mqtt
        image: $Z2M_IMAGE
        volumes:
            - $DATA_SHARE/data/mosquitto/zigbee2mqtt_data/:/app/data/
            - /run/udev:/run/udev:ro
        devices:
            - $Z2M_DEVICE:/dev/ttyACM0
        restart: always
        privileged: true
        environment:
            - TZ=$TIMEZONE
EOF
    fi
done

curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

usermod -aG docker $USER

cd $DATA_SHARE

echo "Installing ...."
#docker-compose up -d  > /dev/null 2>&1
docker-compose up -d


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
    url: https://${DOMAIN}fed
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
    url: https://${DOMAIN}esp
    require_admin: true
EOF

cat << EOF >> $DATA_SHARE/data/homeassistant/packages/panel_duplicati.yaml
panel_iframe:
  duplicati:
    title: Duplicati
    icon: mdi:file-restore
    url: https://${DOMAIN}dup
    require_admin: true
EOF

cat << EOF >> $DATA_SHARE/data/homeassistant/packages/panel_portainer.yaml
panel_iframe:
  portainer:
    title: Portainer
    icon: mdi:docker
    url: https://${DOMAIN}port
    require_admin: true
EOF

cat << EOF >> $DATA_SHARE/data/homeassistant/packages/sql.yaml
recorder:
  db_url: mysql://$SQL_USR:$SQL_PWD@$IP_ADDRESS:3308/$SQL_DB?charset=utf8mb4
  commit_interval: 60
sensor:
  - platform: sql
    db_url: mysql://$SQL_USR:$SQL_PWD@$IP_ADDRESS:3308/$SQL_DB
    queries:
      - name: db_size
        query: 'SELECT table_schema "database", Round(Sum(data_length + index_length) / 1024 / 1024, 1) "value" FROM information_schema.tables WHERE table_schema="$SQL_DB" GROUP BY table_schema;'
        column: 'value'
        unit_of_measurement: Mb
EOF
rm $DATA_SHARE/data/homeassistant/home-assistant_v2.db
docker restart homeassistant
