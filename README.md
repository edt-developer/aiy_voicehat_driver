# Google AIY Voice HAT Kernel Driver Fix

## Problem

The Voice HAT uses ICS43432 MEMS microphones that output 24-bit left-justified I2S
data. The stock kernel driver declares the capture format as `S32_LE` (signed 32-bit
little endian), which causes the 24-bit data to sit in the **lower** 24 bits of the
32-bit container. This makes recordings ~40 dB too quiet -- effectively silent.

## The Fix

Changed the capture format from `SNDRV_PCM_FMTBIT_S32_LE` to `SNDRV_PCM_FMTBIT_S24_LE`.
This tells the ALSA core to interpret the data as 24-bit left-justified in a 32-bit
container (upper 24 bits = data, lower 8 bits = padding), shifting it properly.

**Result:** Signal level improved from ~0.25% to ~3.4% of full scale (+22 dB).

---

## Prerequisites

1. Check /boot/firmware/config.txt and make sure the Voice HAT overlay is enabled:

```
dtoverlay=googlevoicehat-soundcard
```

2. Ensure there is not another overlay that conflicts with the googlevoicehat overlay (e.g. `hifiberry-dac`). I believe its only the I2S pins that conflict, so you might be able to use a different sound card if it doesn't also use the I2S mics. But I haven't tested this.

3. To gain control over the mic levels, you probably need wireplumber, pipewire.

4. Note: this sound card also has a I2S DAC output for a speaker or headphones.

## Building the Module

### Option 1. use the installer script (recommended):
```bash
make build
sudo make install
```

### Option 2. build manually - *** THIS IS OLD, THE MAKEFILE NOW DOES ALL THIS***

Prerequisites (already installed on this system):
```
sudo apt install linux-headers-$(uname -r)
```

Build:
```bash
make
```

This produces `googlevoicehat-codec.ko` in the current directory.

---

## Installing the Module

### Step 1: Back up the original
```bash
# The stock module is a compressed .ko.xz file
ORIG=/lib/modules/$(uname -r)/kernel/sound/soc/bcm/snd-soc-googlevoicehat-codec.ko.xz
sudo cp $ORIG ${ORIG}.bak
```

### Step 2: Unload the current driver
```bash
# Stop all audio services so nothing is using the device
systemctl --user stop pipewire.socket pipewire wireplumber
sleep 2

# Unload the sound card driver first (it holds a ref on the codec)
sudo modprobe -r snd_soc_rpi_simple_soundcard

# Then unload the codec driver
sudo modprobe -r snd_soc_googlevoicehat_codec
```

### Step 3: Install the fixed module
```bash
# Copy the built .ko file (uncompressed .ko replaces both .ko and .ko.xz)
sudo cp googlevoicehat-codec.ko \
  /lib/modules/$(uname -r)/kernel/sound/soc/bcm/snd-soc-googlevoicehat-codec.ko

# Rebuild module dependency tree
sudo depmod -a
```

### Step 4: Reload the driver
```bash
# Load codec first, then the soundcard that depends on it
sudo modprobe snd_soc_googlevoicehat_codec
sudo modprobe snd_soc_rpi_simple_soundcard

# Restart audio services
systemctl --user start pipewire.service wireplumber.service
sleep 2
```
### Better to reboot at this point! This ensures the new module is loaded properly and all services are restarted cleanly.

### Step 5: Verify
```bash
# Check the module is loaded with our patched srcversion
modprobe -c | grep googlevoicehat
ls -l /lib/modules/$(uname -r)/kernel/sound/soc/bcm/snd-soc-googlevoicehat-codec.ko*

# Should see card 3 with capture:
arecord -l
```

---

## Testing

Record 5 seconds from the Voice HAT mic:
```bash
arecord -Dhw:3,0 -f S32_LE -c 2 -r 48000 -d 5 /tmp/voice_test.wav
```

Play it back through the OontZ Angle:
```bash
paplay /tmp/voice_test.wav
```

Playback with +15 dB userspace gain (mics are still modest at ~3.4% full scale):
```bash
ffmpeg -y -i /tmp/voice_test.wav -af "volume=15dB" -f wav - | paplay
```

---

## Quick One-Liner: Record, Amplify, Play
```bash
arecord -Dhw:3,0 -f S32_LE -c 2 -r 48000 -d 5 /tmp/test.wav && \
  ffmpeg -y -i /tmp/test.wav -af "volume=15dB" -f wav - | paplay
```

---

## Applying the Patch to Upstream Source

If you need to re-patch against a fresh upstream copy from the raspberrypi/linux repo:
```bash
# Download upstream file from rpi-6.12.y branch
wget https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.12.y/sound/soc/bcm/googlevoicehat-codec.c

# Apply our patch
patch googlevoicehat-codec.c < googlevoicehat-codec.patch
```

---

## After a Kernel Update

When you update the kernel, the module path changes and you need to rebuild:
```bash
make clean
make
# Then follow the "Installing the Module" steps above again
```
