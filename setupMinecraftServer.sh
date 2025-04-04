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
  # Erst checken wir mit der Mojang-API, ob die Version existiert
  echo "Prüfe Existenz der Minecraft-Version $MC_VERSION..."
  MC_SERVER_URL=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json | jq -r ".versions[] | select(.id==\"$MC_VERSION\") | .url")

  if [ -n "$MC_SERVER_URL" ] && [ "$MC_SERVER_URL" != "null" ]; then
    # Jetzt noch prüfen, ob Version unter 1.8 ist -> nicht zulassen
    # Dazu parsen wir die eingegebene Version in einzelne Zahlen
    IFS='.' read -r VMAJOR VMINOR VPATCH <<< "$MC_VERSION"
    # Falls Patch leer ist, auf 0 setzen
    VPATCH="${VPATCH:-0}"

    # Version als "Ganzzahl" kodieren, um diese leichter zu vergleichen (z.B. 1.16.5 -> 11605)
    versionToInt() {
      local major=$1
      local minor=$2
      local patch=$3
      echo $(( major * 10000 + minor * 100 + patch ))
    }

    CURRENT_VER_INT=$(versionToInt "$VMAJOR" "$VMINOR" "$VPATCH")

    # Vergleichswerte für relevante Schwellen
    V_1_8_0=10800
    V_1_12_0=11200
    V_1_16_5=11605
    V_1_17_0=11700
    V_1_20_0=12000

    # Unter Minecraft 1.8 wird nicht zugelassen
    if [ "$CURRENT_VER_INT" -lt "$V_1_8_0" ]; then
      echo "Versionen unter 1.8 sind nicht zugelassen! (Eingegeben: $MC_VERSION)"
      continue
    fi

    # Passende Java-Version wird bestimmt:
    if [ "$CURRENT_VER_INT" -lt "$V_1_12_0" ]; then
      # 1.8.x bis 1.11.x
      DESIRED_JAVA_VERSION=8
    elif [ "$CURRENT_VER_INT" -le "$V_1_16_5" ]; then
      # 1.12.0 bis einschließlich 1.16.5
      DESIRED_JAVA_VERSION=11
    elif [ "$CURRENT_VER_INT" -lt "$V_1_20_0" ]; then
      # 1.17.x bis 1.19.x
      DESIRED_JAVA_VERSION=17
    else
      # ab 1.20
      DESIRED_JAVA_VERSION=21
    fi

    echo "Version $MC_VERSION ist gültig. Benötigte Java-Version: $DESIRED_JAVA_VERSION"
    break
  else
    echo "Die angegebene Minecraft-Version '$MC_VERSION' existiert nicht! Bitte erneut eingeben."
  fi
done

# Java passend zur gewünschten Version installieren (OpenJDK)
# ------------------------------------------------------------
echo "Installiere OpenJDK $DESIRED_JAVA_VERSION (headless)..."
apt-get -qq update
apt-get -qq install "openjdk-$DESIRED_JAVA_VERSION-jre-headless" -y
echo "OpenJDK $DESIRED_JAVA_VERSION erfolgreich installiert."

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

# eula.txt erstellen und auf true setzen
echo "Erstelle eula.txt..."
echo "eula=true" > "$INSTALL_DIR/minecraft-server/eula.txt"

# Erstellen der start.sh
echo "Erstelle start.sh Datei..."
cat <<EOL > "$INSTALL_DIR/minecraft-server/start.sh"
#!/bin/bash
screen -dmS minecraft-server java -Xmx2048M -Xms1024M -jar server.jar nogui
EOL

# Rechte für start.sh setzen
chmod +x "$INSTALL_DIR/minecraft-server/start.sh"
echo "start.sh wurde erstellt und ausführbar gemacht."

echo "---------------------------------------------------"
echo "           INSTALLATION ERFOLGREICH!"
echo "---------------------------------------------------"
echo "Dein Server befindet sich in: $INSTALL_DIR/minecraft-server"
echo "Starte ihn dort einfach mit: ./start.sh"
echo "---------------------------------------------------"
