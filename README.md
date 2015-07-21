# codeshower
This README will serve as a detail on the files in this git with a brief explanation of their purpose.

LINUXMCE

LMCE is a home automation platform covering media, lighting, security, telecom, etc. There is a core server, which can operate as a hybrid core/media director, that at its heart is a very elegant messaging bus and router. Other media directors network boot to the server and attach to monitors/TVs which serve as the primary human interface. The system can be controlled by any interface attached to the system. For instance any remote control you have in your home can control anything in your home. The messaging bus serializes data and allows any event to control anything on the network. Eg: If media is started in a room, it will dim the lights to theater lighting... if there is an incoming phone call, it wakes all monitors in the home, pauses media, and allows you to accept or decline the call from any input medium, including voice. Homes can be connected to each other over a WAN. Files from this project are mostly BASH scripts employing automation solutions.

linuxmce/Utils.sh
linuxmce/VideoDetectSetup
linuxmce/AVWizard_Run.sh
Purpose: Utils.sh is a toolbox for various automated hardware identification and installation for customized utilization. The primary chunk of code corroborates with VideoDetectSetup, and installs the correct driver for any GPU in existence, and in conjunction with AVWizard_Run.sh, generates a custom xorg.conf file utilizing hardware acceleration, if available, across all vendors. I make my best effort to do edge detection creating a custom modeline, but depending on the TV/monitor and how it handles overscanning, sizing can be achieved through the AVWizard. Script appropriately handles multiple cards, determining the “best” GPU as the system interface. Also detects and generates customized ALSA configuration for any type of audio card to work based on the preferences selected during the AVWizard setup interface (eg HDMI, analog, SPDIF etc).
See: http://wiki.linuxmce.org/index.php/AV_Wizard_Step_by_Step

linuxmce/image.sh
linuxmce/lmcemaster.sh
Purpose: These scripts automate the creation of an installable DVD ISO from the builder, pre-loaded with all of the features and current database builds. image.sh creates a bootstrapped blank slate dd image of the project on the builder, and lmcemaster.sh masters an ISO from that image. It is a bit of a monster, but generates a universally installable image for our proprietary distribution on just about any hardware or virtual environment. There is a lot of hacking in here, but the result is a remarkably hardware agnostic installer that can be churned ad-hock to spin updated images. The ISO contains a working live boot system without any software install as well.

linuxmce/dvd-installer.sh
Purpose: This hydra detects hardware, installs, and configures the entire system on the hardware. There is a lot of code to sift through here, but it is driven by a lot of solutions. It sorts out single or dual NICs (it is, after all, primarily a DCE router), and automates the process completely. After the initial install, it reboots itself a couple of times and dumps you into the AVWizard, which allows you to specify your audio/visual preferences/requirements, per station. There is a sister script which runs on the moons when they are first attached to the system, as well as a net install script. The nightmare of installation prior to the DVD image and these scripts relegated the projects popularity only to experienced Linux users/developers and professional installers and took about six hours. Now that I have automated it, pretty much anyone can install the latest snapshot, on almost anything, in about a third of the time of a typical Windows install.
See: http://wiki.linuxmce.org/index.php/Installing_1004

linuxmce/StorageDevicesRadar.sh
Problem: The Hardware Abstraction Layer (HAL) in most Linux distros was put to bed, which the project relied heavily on. This was the first step in divorcing HAL from the project.

Solution: Automate detection of storage devices with UDEV.

Improvements: Faster, able to detect and alert user of volume details without mounting first. More accurate reporting. More volume types detected including RAID handling. Increased size detection to exabytes.

linuxmce/gstreamer-player
Purpose: This is a very flexible, very light weight snap-in gstreamer written in C. When paired with the   Good Bad and Ugly video codec bundles and libdvdcss2 will play just about any media type there is, with a great deal of control. While originally intended as a media solution for the QT extension of the LMCE media director interface, is versatile enough and fully embeddable for endless applications. VDPAU is only acceleration currently accounted for.
Prerequisites for compiling: gstreamer-0.10, gtk+2, possibly the gstreamer sdk, depending on your distribution. 
http://docs.gstreamer.com/display/GstSDK/Installing+on+Linux
