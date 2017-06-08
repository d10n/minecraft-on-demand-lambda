#!/bin/bash
yum update -y
mkdir MinecraftServer
aws s3 sync s3://mc-world-backup MinecraftServer/
cd MinecraftServer
crontab -l | { cat; echo "*/5 * * * * aws s3 sync /MinecraftServer/ s3://mc-world-backup"; } | crontab -
sudo java -Xmx1G -Xms1G -jar minecraft_server.1.11.2.jar nogui