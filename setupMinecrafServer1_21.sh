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
    echo "Installationspfad gesetzt: $INSTALL_DIR"
    break
  else
    echo "Ungültiger Pfad! Bitte einen vorhandenen Pfad angeben."
  fi
done

# Prüfen und ggf. Installation von curl und jq
for tool in curl jq; do
  if ! command -v $tool &>/dev/null; then
    echo "$tool ist nicht installiert. Installiere $tool..."
    apt-get -qq update && apt-get -qq install $tool -y
    echo "$tool wurde installiert."
  fi
done

# Abfrage und Prüfung der gewünschten Minecraft-Version
while true; do
  read -p "Welche Minecraft-Version soll installiert werden (z.B. 1.21.5)? " MC_VERSION
  echo "Prüfe Existenz der Minecraft-Version $MC_VERSION..."
  MC_SERVER_URL=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json | jq -r ".versions[] | select(.id==\"$MC_VERSION\") | .url")

  if [ -n "$MC_SERVER_URL" ] && [ "$MC_SERVER_URL" != "null" ]; then
    echo "Version $MC_VERSION gefunden."
    break
  else
    echo "Die angegebene Minecraft-Version existiert nicht! Bitte erneut eingeben."
  fi
done

# Prüfen, ob Java 23 bereits installiert ist
if java -version 2>&1 | grep -q '23'; then
  echo "Java 23 ist bereits installiert."
  update_java="n"
elif java -version &>/dev/null; then
  JAVA_INSTALLED_VERSION=$(java -version 2>&1 | head -n 1)
  echo "Java ist bereits installiert: $JAVA_INSTALLED_VERSION"
  read -p "Möchtest du auf Java 23 aktualisieren? (j/n): " update_java
else
  update_java="j"
fi

if [[ "$update_java" =~ ^[Jj]$ ]]; then
  echo "Installiere Java 23..."
  wget -qO /tmp/jdk-23_linux-x64_bin.deb https://download.oracle.com/java/23/latest/jdk-23_linux-x64_bin.deb
  apt-get -qq install /tmp/jdk-23_linux-x64_bin.deb -y
  rm /tmp/jdk-23_linux-x64_bin.deb
  echo "Java 23 wurde installiert."
fi

# Aktualisieren der Paketlisten und Upgrade des Systems
echo "Aktualisiere Paketlisten und System..."
apt-get -qq update && apt-get -qq upgrade -y

# Benötigte Pakete installieren
for pkg in screen wget apt-transport-https gpg; do
  if ! dpkg -l | grep -qw $pkg; then
    echo "Installiere Paket: $pkg..."
    apt-get -qq install $pkg -y
  else
    echo "Paket $pkg bereits installiert."
  fi
done

# Minecraft-Server Verzeichnis erstellen
echo "Erstelle Minecraft-Server Verzeichnis..."
mkdir -p "$INSTALL_DIR/minecraft-server"

# Server JAR URL abrufen
echo "Server JAR URL wird abgerufen..."
SERVER_JAR_URL=$(curl -s "$MC_SERVER_URL" | jq -r ".downloads.server.url")
echo "Server JAR URL erhalten."

# Herunterladen der Minecraft Server-JAR
echo "Lade Minecraft Server JAR herunter..."
wget -qO "$INSTALL_DIR/minecraft-server/server.jar" "$SERVER_JAR_URL"
echo "Server JAR erfolgreich heruntergeladen."

# eula.txt erstellen
echo "Erstelle eula.txt..."
echo eula=true > "$INSTALL_DIR/minecraft-server/eula.txt"

# Erstellen der start.sh
echo "Erstelle start.sh Datei..."
cat <<EOL > "$INSTALL_DIR/minecraft-server/start.sh"
#!/bin/bash
screen -dmS minecraft-server java -Xmx2048M -Xms1024M -jar server.jar nogui
EOL

# Rechte für start.sh setzen
chmod +x "$INSTALL_DIR/minecraft-server/start.sh"
echo "start.sh wurde erstellt und ausführbar gemacht."

# Abschlussmeldung
echo "---------------------------------------------------"
echo "           INSTALLATION ERFOLGREICH!"
echo "---------------------------------------------------"
echo "Dein Server befindet sich in: $INSTALL_DIR/minecraft-server"
echo "Starte ihn mit: ./start.sh"
echo "---------------------------------------------------"
