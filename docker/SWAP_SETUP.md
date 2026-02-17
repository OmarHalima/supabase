# Swap setup (VPS safety net)

This repo’s self-hosting setup benefits from having some swap configured on the VPS. Swap is **not for performance**; it’s a **stability/safety net** that helps prevent the kernel from OOM-killing containers during memory spikes.

## What we configured

- **Swap type**: swapfile
- **Path**: `/swapfile`
- **Size**: 8 GiB
- **Permissions**: `0600`
- **Persistence**: `/etc/fstab` entry added
- **Swappiness**: `vm.swappiness=10` (reduce swapping aggressiveness)

## Commands used

### 1) Check current state

```bash
df -h /
free -h
swapon --show
```

### 2) Create and enable an 8GiB swapfile

```bash
sudo fallocate -l 8G /swapfile

# If fallocate fails, use dd instead:
# sudo dd if=/dev/zero of=/swapfile bs=1M count=8192 status=progress

sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### 3) Make it persistent across reboot

```bash
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### 4) (Optional but recommended) Reduce swapping aggressiveness

```bash
sudo sysctl vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
```

## Verify

```bash
swapon --show
free -h
sysctl vm.swappiness
```

Expected:
- `swapon --show` lists `/swapfile`
- `free -h` shows Swap total as `8.0Gi`
- `vm.swappiness = 10`

## Remove (undo)

```bash
sudo swapoff /swapfile
sudo rm -f /swapfile

# Remove the line from /etc/fstab:
# /swapfile none swap sw 0 0

sudo rm -f /etc/sysctl.d/99-swappiness.conf
```

