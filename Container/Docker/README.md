# Docker Utilities

Container management utilities for Docker cleanup and maintenance operations.

## Scripts

### `remove_dengling_images.sh`
Removes unused Docker images to free up disk space.

**Features:**
- Removes dangling (untagged) images
- Safe cleanup without affecting running containers
- Displays space reclaimed after cleanup

**Usage:**
```bash
./remove_dengling_images.sh
```

### `stop_and_remove_all.sh`
Complete Docker environment cleanup - stops and removes all containers, images, and networks.

**⚠️ Warning:** This script performs a complete Docker environment reset. Use with caution in production environments.

**Features:**
- Stops all running containers
- Removes all containers (running and stopped)
- Removes all Docker images
- Removes all custom networks
- Removes all volumes
- Comprehensive cleanup for fresh start

**Usage:**
```bash
# Review what will be removed first
docker ps -a
docker images
docker network ls
docker volume ls

# Perform cleanup
./stop_and_remove_all.sh
```

## Safety Notes

1. **Backup Important Data:** Ensure all important data is backed up before running cleanup scripts
2. **Development Only:** These scripts are intended for development environments
3. **Production Caution:** Never run `stop_and_remove_all.sh` in production without proper backups
4. **Review First:** Always review running containers and images before cleanup

## Integration with Main Setup Script

These utilities complement the main `ubuntu-server-setup.sh` script and can be used for:
- Pre-installation cleanup
- Development environment maintenance  
- Troubleshooting Docker issues
- Regular maintenance tasks