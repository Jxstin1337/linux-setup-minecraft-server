#!/bin/bash

# Prüfen, ob das Skript mit Root-Rechten oder sudo ausgeführt wird
if [ "$(id -u)" -ne 0 ]; then
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

# Abfrage vom Namen des Serverordner
while true; do
  read -rp "Wie soll der Minecraft-Server-Ordner heißen (z.B. mc-server-1)? " SERVER_FOLDER_NAME

  # Auf ungültige Zeichen prüfen (nur Buchstaben, Zahlen, Bindestrich, Unterstrich erlaubt)
  if [[ ! "$SERVER_FOLDER_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Ungültiger Ordnername! Nur Buchstaben, Zahlen, Bindestriche (-) und Unterstriche (_) erlaubt."
    continue
  fi

  FULL_PATH="$INSTALL_DIR/$SERVER_FOLDER_NAME"

  if [ -d "$FULL_PATH" ]; then
    echo "Ordner $FULL_PATH existiert bereits! Bitte anderen Namen wählen."
  else
    echo "Serververzeichnis wird: $FULL_PATH"
    break
  fi
done

# jq und curl prüfen und ggf. installieren
for tool in curl jq; do
  if ! command -v "$tool" &>/dev/null; then
    echo "$tool ist nicht installiert. Versuche, $tool zu installieren..."
    apt-get update && apt-get install -y "$tool"
    
    if ! command -v "$tool" &>/dev/null; then
      echo "Fehler: $tool konnte nicht installiert werden. Bitte manuell prüfen."
      exit 1
    fi

    echo "$tool wurde erfolgreich installiert."
  else
    echo "$tool ist bereits installiert."
  fi
done

# Funktion zur Überprüfung der installierten Java-Version
check_java_version() {
  if command -v java &>/dev/null; then
    local current_version
    current_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    IFS='.' read -r MAJ MIN PATCH <<< "${current_version//_/\.}"

    if [[ "$MAJ" -ge 9 ]]; then
      CURRENT_JAVA="$MAJ"
    else
      CURRENT_JAVA="$MIN"
    fi
    echo "$CURRENT_JAVA"
  else
    echo "none"
  fi
}

# Abfrage und Prüfung der gewünschten Minecraft-Version
while true; do
  read -p "Welche Minecraft-Version soll installiert werden (z.B. 1.21.5)? " MC_VERSION
  echo "Prüfe Existenz der Minecraft-Version $MC_VERSION..."
  MC_SERVER_URL=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json | jq -r ".versions[] | select(.id==\"$MC_VERSION\") | .url")

  if [ -n "$MC_SERVER_URL" ] && [ "$MC_SERVER_URL" != "null" ]; then
    IFS='.' read -r VMAJOR VMINOR VPATCH <<< "$MC_VERSION"
    VPATCH="${VPATCH:-0}"

    versionToInt() {
      local major=$1
      local minor=$2
      local patch=$3
      echo $(( major * 10000 + minor * 100 + patch ))
    }

    CURRENT_VER_INT=$(versionToInt "$VMAJOR" "$VMINOR" "$VPATCH")

    V_1_8_0=10800
    V_1_12_0=11200
    V_1_16_5=11605
    V_1_20_0=12000

    if [ "$CURRENT_VER_INT" -lt "$V_1_8_0" ]; then
      echo "Versionen unter 1.8 sind nicht zugelassen! (Eingegeben: $MC_VERSION)"
      continue
    fi

    if [ "$CURRENT_VER_INT" -lt "$V_1_12_0" ]; then
      DESIRED_JAVA_VERSION=8
    elif [ "$CURRENT_VER_INT" -le "$V_1_16_5" ]; then
      DESIRED_JAVA_VERSION=11
    elif [ "$CURRENT_VER_INT" -lt "$V_1_20_0" ]; then
      DESIRED_JAVA_VERSION=17
    else
      DESIRED_JAVA_VERSION=21
    fi

    echo "Version $MC_VERSION ist gültig. Benötigte Java-Version: $DESIRED_JAVA_VERSION"

    CURRENT_INSTALLED_JAVA=$(check_java_version)
    if [ "$CURRENT_INSTALLED_JAVA" = "none" ]; then
      echo "Kein Java installiert. OpenJDK $DESIRED_JAVA_VERSION wird installiert."
    elif [ "$CURRENT_INSTALLED_JAVA" -ne "$DESIRED_JAVA_VERSION" ]; then
      echo "Aktuell installierte Java-Version: $CURRENT_INSTALLED_JAVA"
      read -p "Möchtest du stattdessen Java $DESIRED_JAVA_VERSION installieren? (j/n): " CONFIRM_JAVA
      if [[ "$CONFIRM_JAVA" != "j" && "$CONFIRM_JAVA" != "J" ]]; then
        echo "Installation abgebrochen. Bitte passende Java-Version manuell installieren."
        exit 1
      fi
    else
      echo "Benötigte Java-Version $DESIRED_JAVA_VERSION ist bereits installiert."
    fi

    break
  else
    echo "Die angegebene Minecraft-Version '$MC_VERSION' existiert nicht! Bitte erneut eingeben."
  fi
done

# Java ggf. installieren
if ! command -v java &>/dev/null || [ "$CURRENT_INSTALLED_JAVA" -ne "$DESIRED_JAVA_VERSION" ]; then
  echo "Installiere OpenJDK $DESIRED_JAVA_VERSION (headless)..."
  apt-get update && apt-get install -y "openjdk-$DESIRED_JAVA_VERSION-jre-headless"
  echo "OpenJDK $DESIRED_JAVA_VERSION erfolgreich installiert."
fi

# Benötigte Zusatzpakete installieren
for pkg in screen wget apt-transport-https gpg; do
  if ! dpkg -l | grep -qw "$pkg"; then
    echo "Installiere Paket: $pkg..."
    apt-get install -y "$pkg"
  else
    echo "Paket $pkg bereits installiert."
  fi
done

# Minecraft-Server-Verzeichnis anlegen
echo "Erstelle Minecraft-Server Verzeichnis..."
mkdir -p "$FULL_PATH"

# Server JAR URL abrufen
echo "Server JAR URL wird abgerufen..."
SERVER_JAR_URL=$(curl -s "$MC_SERVER_URL" | jq -r ".downloads.server.url")
echo "Server JAR URL erhalten."

# Server-JAR herunterladen
echo "Lade Minecraft Server JAR herunter..."
wget -qO "$FULL_PATH/server.jar" "$SERVER_JAR_URL"
echo "Server JAR erfolgreich heruntergeladen."

# eula.txt akzeptieren
echo "Erstelle eula.txt..."
echo "eula=true" > "$FULL_PATH/eula.txt"

# Start-Skript erzeugen
echo "Erstelle start.sh Datei..."
cat <<EOL > "$FULL_PATH/start.sh"
#!/bin/bash
screen -dmS $SERVER_FOLDER_NAME java -Xmx2048M -Xms1024M -jar server.jar nogui
EOL

chmod +x "$FULL_PATH/start.sh"
echo "start.sh wurde erstellt und ausführbar gemacht."

echo "---------------------------------------------------"
echo "           INSTALLATION ERFOLGREICH!"
echo "---------------------------------------------------"
echo "Dein Server befindet sich in: $FULL_PATH"
echo "Starte ihn dort einfach mit: ./start.sh"
echo "---------------------------------------------------"
