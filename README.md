# What is this?
Syncd is an OpenComputers rc.d script for devices on multiplayer servers that runs in the background and constantly pings the python webserver for changes in your project's directory. If it detects there were any, it then proceeds to redownload all new or modified files, and handles deletion too. That way it allows you to comfortably develop your software locally on your machine, while the changes appear in-game almost immediately, much like they would if you were doing that in singleplayer.

# How do I use it?
## Prerequisites
1. Python 3.x
2. Public IP with access to your router so you can do port forwarding, or a VPS (basically you need a public IP to which the script can connect to)
3. Internet card installed in your OC device

## Setup
1. Configure your router to forward traffic on TCP port 8000 to your local machine, and disable firewall on that port. If you're running this on a VPS (where you will have to edit your files) just make sure no firewall is blocking you, ports should be open already.
2. (In OC) Place `syncd.lua` in `/etc/rc.d` catalogue of your OpenOS installation.
3. (In OC) Configure the client

```
rc syncd setAddress <ip address of your machine>:8000
rc syncd setDirectory <path to a directory where the files will be downloaded and updated on your OC device>
rc syncd setPolling 5
```

I Suggest setting polling time (interval between requests to the server) to some comfortable, but not too low value since it can cause missing some keystrokes in the terminal.

4. (On your local machine) On your local machine, run webServerWatcher.py with the following syntax

```
python webServerWatcher.py <path to your observer directory>
```

5. (In OC) Enable syncd to start at bootup and turn it on

```
rc syncd enable
rc syncd start
```

## Is it working?
Now edit something on your local machine in a folder that you supplied as an argument to that python script in step 4. After a short delay you should hear your in-game computer's hard drive writing data to disk. You can check if it actually updated the file as well, but the former should be a good indication.

# Limitations
Currently it only supports one client and will exhibit unexpected behaviour if you try to connect multiple clients to the python server, or even check the webpage contents it's serving. Also it redownloads all the files each time you start the python server. This was originally developed for ComputerCraft and HTTP was the only thing available, I know that polling is not the best approach and since TCP sockets are available in OC, I might rewrite this to use them someday.
