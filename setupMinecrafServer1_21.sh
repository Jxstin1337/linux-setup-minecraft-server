#!/bin/bash

# Prüfen, ob das Skript mit Root-Rechten oder sudo ausgeführt wird
if [ $(id -u) -ne 0 ]; then
  echo "Dieses Skript muss mit Root-Rechten oder sudo ausgeführt werden!"
  exit 1
fi

# Abfrage des Installationspfads (Standard: /opt)
while true; do
  echo -n "Pfad für die Installation angeben (Standard: /opt): "
  read -r INSTALL_DIR
  if [ -z "$INSTALL_DIR" ]; then
    INSTALL_DIR="/opt"
  fi

  if [ -d "$INSTALL_DIR" ]; then
    break
  else
    echo "Ungültiger Pfad! Bitte einen vorhandenen Pfad angeben."
  fi
done

# Aktualisieren der Paketlisten und Upgrade des Systems
apt update && apt upgrade -y

# Installation von screen (falls noch nicht vorhanden)
if ! dpkg -l | grep -q screen; then
  apt install screen -y
fi

# Installation von wget (falls noch nicht vorhanden)
if ! dpkg -l | grep -q wget; then
  apt install wget -y
fi

# Installation von apt-transport-https (falls noch nicht vorhanden)
if ! dpkg -l | grep -q apt-transport-https; then
  apt install apt-transport-https -y
fi

# Installation von gpg (falls noch nicht vorhanden)
if ! dpkg -l | grep -q gpg; then
  apt install gpg -y
fi

# Hinzufügen des Adoptium Repositorys
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null
echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list

# Installation von Java 22
apt update # Repository-Listen nach dem Hinzufügen aktualisieren
apt install temurin-22-jdk -y

# Erstellen des Minecraft Server Verzeichnisses
mkdir -p "$INSTALL_DIR/minecraft-server"

# Herunterladen der Server-JAR
wget -O "$INSTALL_DIR/minecraft-server/server.jar" https://piston-data.mojang.com/v1/objects/450698d1863ab5180c25d7c804ef0fe6369dd1ba/server.jar

# Erstellen der eula.txt
echo eula=true > "$INSTALL_DIR/minecraft-server/eula.txt"

# Erstellen der start.sh
echo '#!/bin/bash' > "$INSTALL_DIR/minecraft-server/start.sh"
echo 'screen -dmS minecraft-server java -Xmx2048M -Xms1024M -jar server.jar nogui' >> "$INSTALL_DIR/minecraft-server/start.sh"

# Rechtezuweisung der start.sh
chmod +x "$INSTALL_DIR/minecraft-server/start.sh"

# Erfolgsmeldung und Hinweis zum Starten des Servers
echo "---------------------------------------------------"
echo "           INSTALLATION ERFOLGREICH!"
echo "---------------------------------------------------"
echo "Dein Server befindet sich in $INSTALL_DIR/minecraft-server"
echo "Du kannst ihn dort mit [sudo] ./start.sh starten"
echo "---------------------------------------------------"
