# AnkerMake M5 Protocol 2026 Edition

Welcome! This repository contains `ankerctl`, a command-line interface and web UI for monitoring, controlling, and interfacing with AnkerMake M5 and M5C 3D printers.

The `ankerctl` program uses [`libflagship`](documentation/developer-docs/libflagship.md), a library for communicating with the numerous different protocols required for connecting to an AnkerMake M5 or M5C printer. The `libflagship` library is also maintained in this repo, under [`libflagship/`](libflagship/).

![Screenshot of ankerctl](/documentation/web-interface.png "Screenshot of ankerctl web interface")

## Features

### Current Features

- Print directly from PrusaSlicer and its derivatives (SuperSlicer, Bambu Studio, OrcaSlicer, etc.).

- Connect to AnkerMake M5/M5C printers and AnkerMake APIs without using closed-source Anker software.

- Send raw G-code commands to the printer and view the response.

- Use low-level MQTT, PPPP, and HTTPS APIs.

- Send print jobs (G-code files) to the printer.

- Stream camera images and video to your computer (AnkerMake M5 only).

- Monitor print status.

### Integrations

- **Home Assistant**: `ankerctl` ships with a native Home Assistant custom component. Copy the `custom_components/ankermake` directory into your Home Assistant `config/custom_components` folder, restart Home Assistant, and select **Add Integration** to import your AnkerMake printers and their live MQTT sensors into your dashboard.

## Installation

Choose one installation method:

- [Install directly from Git](documentation/install-from-git.md) (recommended). This requires Python 3.10 or later.
- [Install with Docker](documentation/install-from-docker.md). The Docker image is built locally from this repository.

After installing, authenticate your AnkerMake account before starting the web interface or using printer commands.

## Authenticating your Account

From the root `ankermake-m5-protocol` directory, run the login command for your installation method.

Git installation:

```sh
./ankerctl.py config login
```

Docker installation:

```sh
docker compose run --rm ankerctl config login
```

You will be asked for your AnkerMake email address, password, and two-letter country code. For authentication options, CAPTCHA handling, and troubleshooting, read the [Login Instructions](documentation/login-instructions.md).

To verify the imported account and printers, run `config show` using the same installation method:

```sh
# Git installation
./ankerctl.py config show

# Docker installation
docker compose run --rm ankerctl config show
```

> **Important:** The cached configuration contains sensitive credentials, including your authentication token and MQTT user ID. Do not share the configuration files or unredacted command output.

Run a command with `-h` or `--help` to see its available options. The webserver process or Docker service must remain running while you use the web interface or print from a slicer.

## Usage

### Web Interface

1. Start the webserver from the repository directory using the command for your installation method:

   Docker installation:

   ```sh
   docker compose up -d
   ```

   Git installation:

   ```sh
   ./ankerctl.py webserver run
   ```

2. Open [http://localhost:4470](http://localhost:4470) on the computer running `ankerctl`. When accessing a Docker host from another computer on the same network, replace `localhost` with the Docker host's IP address.

> **Important:** You must complete the authentication step before using the web interface. Once authenticated, the page provides access to printer status and available cameras.

### Printing Directly from PrusaSlicer

`ankerctl` allows slicers such as PrusaSlicer and its derivatives to send print jobs to the printer using the slicer's built-in communication tools. The webserver must be running to receive jobs.

The printer cannot store uploaded jobs for later use, so select **Send and Print** to start the job immediately after transfer.

Additional instructions can be found in the web interface.

![Screenshot of prusa slicer](/static/img/setup/prusaslicer-2.png "Screenshot of prusa slicer")

### Command-line tools

These examples use the Git installation:

```sh
# run the webserver for the web UI
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

# select a printer when you have more than one (index starts at 0)
./ankerctl.py -p <index> <command>
```
