#!/bin/bash
yum update -y
yum install java-1.8.0 -y
yum remove java-1.7.0-openjdk -y
mkdir MinecraftServer
aws s3 sync s3://mc-world-backup MinecraftServer/
cd MinecraftServer
pip install mcstatus
crontab -l | { cat; echo "*/5 * * * * aws s3 sync /MinecraftServer/ s3://mc-world-backup"; } | crontab -
crontab -l | { cat; echo "*/5 * * * * python /MinecraftServer/auto_shutoff.py"; } | crontab -
sudo java -Xmx1G -Xms1G -jar minecraft_server.1.12.jar nogui
