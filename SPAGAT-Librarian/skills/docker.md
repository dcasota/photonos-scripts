# docker - Container Management

Docker container operations on Photon OS.

## Commands

### Status
- Running containers: `docker ps`
- All containers: `docker ps -a`
- Images: `docker images`
- Disk usage: `docker system df`
- Info: `docker info`

### Container Operations
- Run: `docker run -d --name <name> <image>`
- Stop: `docker stop <container>`
- Start: `docker start <container>`
- Remove: `docker rm <container>`
- Logs: `docker logs --tail 50 <container>`
- Exec into: `docker exec -it <container> /bin/sh`
- Inspect: `docker inspect <container>`

### Image Operations
- Pull: `docker pull <image>`
- Build: `docker build -t <tag> .`
- Remove image: `docker rmi <image>`
- Prune unused: `docker image prune -f`

### Cleanup
- Remove stopped: `docker container prune -f`
- Full cleanup: `docker system prune -f`

## Notes
- Service: `systemctl status docker`
- Socket: /var/run/docker.sock
- Config: /etc/docker/daemon.json
