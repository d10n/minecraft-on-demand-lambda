#!/bin/bash
yum update -y
mkdir MinecraftServer
cd MinecraftServer
wget https://s3.amazonaws.com/Minecraft.Download/versions/1.11.2/minecraft_server.1.11.2.jar
cat >eula.txt<<EOF
#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://account.mojang.com/documents/minecraft_eula).
#Tue Jan 27 21:40:00 UTC 2015
eula=true
EOF
sudo java -Xmx1G -Xms1G -jar minecraft_server.1.11.2.jar nogui