# AnkerMake M5 Protocol

Welcome! This repository contains `ankerctl`, a command-line interface and web UI for monitoring, controlling and interfacing with AnkerMake M5 and M5C 3D printers.

The `ankerctl` program uses [`libflagship`](documentation/developer-docs/libflagship.md), a library for communicating with the numerous different protocols required for connecting to an AnkerMake M5 or M5C printer. The `libflagship` library is also maintained in this repo, under [`libflagship/`](libflagship/).

![Screenshot of ankerctl](/documentation/web-interface.png "Screenshot of ankerctl web interface")

## Features

### Current Features

 - Print directly from PrusaSlicer and its derivatives (SuperSlicer, Bamboo Studio, OrcaSlicer, etc.)

 - Connect to AnkerMake M5/M5C and AnkerMake APIs without using closed-source Anker software.

 - Send raw gcode commands to the printer (and see the response).

 - Low-level access to MQTT, PPPP and HTTPS APIs.

 - Send print jobs (gcode files) to the printer.

 - Stream camera image/video to your computer (AnkerMake M5 only).

 - Easily monitor print status.

### Integrations

- **Home Assistant**: `ankerctl` now ships with a native Home Assistant Custom Component! Simply copy the `custom_components/ankermake` directory into your Home Assistant `config/custom_components` folder, restart Home Assistant, and click "Add Integration" to natively import your AnkerMake printers and their live MQTT sensors (Temperature, Print Progress) into your dashboard.

## Installation

There are currently two ways to do an install of ankerctl. You can install directly from git utilizing python on your Operating System or you can install from Docker which will install ankerctl in a containerized environment. Only one installation method should be chosen. 

Order of Operations for Success:
- Choose installation method: [Docker](documentation/install-from-docker.md) or [Git](documentation/install-from-git.md)
- Follow the installation intructions for the install method
- Login to your AnkerMake account
- Have fun! Either run `ankerctl` from CLI or launch the webserver

> **Note**
> Minimum version of Python required is 3.10

Follow the instructions for a [git install](documentation/install-from-git.md) (recommended), or [docker install](documentation/install-from-docker.md).

## Authenticating your Account

1. Import your AnkerMake account data by opening a terminal window in the root `ankermake-m5-protocol` directory and logging in:

   ```sh
   python3 ankerctl.py config login
   ```

   You will be asked to provide your AnkerMake **Email**, **Password**, and **Country Code**.

   > **Note:** For more specific details on authentication options, bypassing Captchas, and verifying your connection, read the [Login Instructions page](documentation/login-instructions.md).

   At this point, your config is saved locally. To see an overview of the stored data and verify your connected printers, use `config show`:

   ```sh
   ./ankerctl.py config show
   [*] Account:
       user_id: 01234567890abcdef012...<REDACTED>
       email:   bob@example.org
       region:  eu
   
   [*] Printers:
       sn: AK7ABC0123401234
       duid: EUPRAKM-001234-ABCDE
   ```

> **NOTE:** 
> The cached login info contains sensitive details. In particular, the `user_id` field is used when connecting to MQTT servers, and essentially works as a password. Thus, the end of the value is redacted when printed to screen, to avoid accidentally disclosing sensitive information.

2. Now that the printer information is known to `ankerctl`, the tool is ready to use. There’s a lot of available commands and utilities, use a command followed by `-h` to learn what your options are and get more in specific usage instructions.

> **NOTE:**
> You must keep the terminal webserver running anytime you wish to use the web interface or print via a slicer.

## Usage

### Web Interface

1. Start the webserver by running one of the following commands in the folder you placed ankerctl in. You’ll need to have this running whenever you want to use the web interface or send jobs to the printer via a slicer:

   Docker Installation Method:

   ```sh
   docker compose up
   ```

   Git Installation Method Using Python:

   ```sh
   ./ankerctl.py webserver run
   ```

2. Navigate to [http://localhost:4470](http://localhost:4470) in your browser of choice on the same computer the webserver is running on. 
 
 > **Important**
 > You must have logged in via `ankerctl.py config login` in your terminal *before* you can use the web interface. Once logged in, the page will load providing access to your cameras and printer status.

### Printing Directly from PrusaSlicer

ankerctl can allow slicers like PrusaSlicer (and its derivatives) to send print jobs to the printer using the slicer’s built in communications tools. The web server must be running in order to send jobs to the printer. 

Currently there’s no way to store the jobs for later printing on the printer, so you’re limited to using the “Send and Print” option only to immediately start the print once it’s been transmitted. 

Additional instructions can be found in the web interface.

![Screenshot of prusa slicer](/static/img/setup/prusaslicer-2.png "Screenshot of prusa slicer")

### Command-line tools

Some examples:

```sh
# run the webserver to control over webgui
./ankerctl.py webserver run

# attempt to detect printers on local network
./ankerctl.py pppp lan-search

# monitor mqtt events
./ankerctl.py mqtt monitor

# start gcode prompt
./ankerctl.py mqtt gcode

# set printer name
./ankerctl.py mqtt rename-printer BoatyMcBoatFace

# print boaty.gcode
./ankerctl.py pppp print-file boaty.gcode

# capture 4mb of video from camera
./ankerctl.py pppp capture-video -m 4mb output.h264

# select printer to use when you have multiple
./ankerctl.py -p <index> # index starts at 0 and goes up to the number of printers you have
```