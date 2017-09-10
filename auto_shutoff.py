#sudo pip install mcstatus
from mcstatus import MinecraftServer
import time
import json
import os.path
import urllib2

server = MinecraftServer.lookup("localhost:25565")
status = server.status()

if os.path.exists('/last_activity'):
	f = open('/last_activity', 'r+')

	if status.players.online:
		f.seek(0)
		f.write(str(time.time()))
		f.truncate()
	else:
		old_time = float(f.read()) 
		time_past = time.time() - old_time
		if time_past > (30*60):
			req = urllib2.urlopen('<SERVER DESTROY LAMBDA FUNCTION>')
else:
	f = open('/last_activity', 'w')
	f.write(str(time.time()))
	
