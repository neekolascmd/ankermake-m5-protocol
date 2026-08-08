# Installation (Docker)

The Docker image is built locally from this repository. The Compose configuration
does not download a prebuilt `ankerctl` image from a container registry.

## Requirements

- [Git](https://git-scm.com/)
- [Docker Engine](https://docs.docker.com/engine/install/) or
  [Docker Desktop](https://docs.docker.com/desktop/) with Docker Compose

## Install

Clone this fork and enter the repository:

```sh
git clone https://github.com/neekolascmd/ankermake-m5-protocol.git
cd ankermake-m5-protocol
```

Build the `ankerctl:latest` image from the included `Dockerfile`:

```sh
docker compose build
```

Log in to your AnkerMake account. This saves the configuration in the persistent
`ankerctl_vol` Docker volume:

```sh
docker compose run --rm ankerctl config login
```

Read the [Login Instructions](login-instructions.md) for additional authentication
options and troubleshooting.

Start `ankerctl` in the background:

```sh
docker compose up -d
```

Open <http://localhost:4470> on the Docker host. From another computer on the same
network, replace `localhost` with the Docker host's IP address.

## Manage the container

Follow the service logs:

```sh
docker compose logs -f ankerctl
```

Stop and remove the container without deleting its persistent configuration:

```sh
docker compose down
```

## Update

Pull the latest source, rebuild the local image, and recreate the container:

```sh
git pull
docker compose up --build -d
```
