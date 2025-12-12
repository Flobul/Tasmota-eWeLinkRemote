# eWeLink Remote Module for Tasmota

## Description

This module enables the use of eWeLink BLE remotes (SNZB-01P and R5) with Tasmota. It provides a web interface to easily configure the associations between remote buttons and Tasmota relays.

## Installation

### Prerequisites:
   - ESP32 with Tasmota installed
   - Berry activated
   - Tasmota [Mi32-bluetooth version](https://github.com/Jason2866/Tasmota-specials/tree/firmware/firmware/tasmota32/other) (file end with *-mi32.bin) 
   - Bluetooth enabled in Tasmota:
   ```
   SetOption115 1
   ```

### Module installation:

#### Manual installation 
   - Download the `ewe_remote.be` file or `ewe_remote_dimmer.be`
   - Copy it to your ESP32 via Tasmota web interface (Console -> Manage File System)
   - Enable it:
   ```
   br load('ewe_remote.be') # or ewe_remote_dimmer.be
   ```

#### Automatic installation 
   - Paste this code in your ESP32 via Tasmota web interface (Console -> Berry Scripting Console)
   ```
   import path

   var base_url = "https://raw.githubusercontent.com/Flobul/Tasmota-eWeLinkRemote/main/"
   var files = {
     'remote': "ewe_remote.be",
     'dimmer': "ewe_remote_dimmer.be",
     'update': "ewe_update.be",
     'config': "ewe_config.json"
   }

   def download_file(filename)
     var cl = webclient()
     cl.begin(base_url + filename)
     if cl.GET() != 200 return false end
     cl.write_file(filename)
     cl.close()
     return true
   end
   
   def start_eweremote_setup()
     var success = true
     
     for name: files.keys()
       print(format("Downloading %s...", files[name]))
       if !download_file(files[name])
         print(format("Error downloading %s", files[name]))
         success = false
         break
       end
     end

     if success
       print("All files downloaded successfully")
       load('ewe_remote.be')  # or ewe_remote_dimmer.be
       return true
     end
     return false
   end
   
   start_eweremote_setup()
   ```
### Load on boot

If you would like a fully berry solution to loading eWeLinkRemote, add the following line to autoexec.be

   ```
    tasmota.add_rule('System#Boot', / -> tasmota.set_timer(10000, / -> load('ewe_remote.be'))) # or ewe_remote_dimmer.be
   ```

Otherwise, you can simply make a rule:

   ```
    Rule1 ON System#Boot DO backlog delay 20; br load('ewe_remote.be') ENDON # or ewe_remote_dimmer.be
   ```
Enable the rule:
   ```
    Rule1 1
   ```

## Configuration

### Web Interface

The module adds a new "eWeLink Remote" button to Tasmota's main menu.

#### Adding a Remote

1. Press any button on the remote
2. The remote appears in the interface
3. Click "Save Device" to register it

#### Remote Aliases

Each remote can be assigned a friendly name (alias):
- Enter the desired name in the text field below the remote ID
- Click "Update Alias" to save
- The alias will be used in MQTT topics when configured (modes 1-3)
- Aliases make it easier to identify remotes in your setup

#### Button Configuration

For each button, you can configure:
- The type of control:
  - Relay: control a specific relay output
  - Dimmer: control brightness level
- Actions that will trigger the control:
  - Single: single click
  - Double: double click
  - Hold: long press
- Click "Add" to create the binding

**Dimmer Configuration**

When "Dimmer" is selected, you can configure:
- Step: dimming step value (1-100, default: 20)
- Min: minimum brightness level (10-1000, default: 10)
- Max: maximum brightness level (0-1000, default: 100)

If SetOption37 >= 128, additional channel options become available:
- All channels (Dimmer0)
- RGB channels (Dimmer1)
- White channels (Dimmer2)
- Linked lights (Dimmer4)

**Dimmer Behavior**
- Single press: toggles between min and max values
- Double press: sets to max value
- Hold: progressively changes brightness
  - First hold increases brightness
  - When max is reached, direction changes to decrease
  - When min is reached, direction changes to increase

**Note**: A single button can control multiple relays with different actions.

### Tasmota Commands

#### Remote Management

```
# List registered remotes
EweAddDevice

# Add a specific remote
EweAddDevice <id>

# Remove a remote
EweRemoveDevice <id>

# Set or modify remote alias
EweAlias <deviceId> <alias>
# Example: EweAlias 5AD9E316 LivingRoom

# List all configured aliases
EweAlias
```

#### Binding Management

```
# Add a relay binding (relay mode)
EweAddBinding <deviceId>_<button>_<relay>_<actions>_<relayAction>
# relayAction can be: toggle, 1 (ON), or 0 (OFF)
# Examples:
#   Toggle relay 1 on single/double click: EweAddBinding 5AD9E316_1_1_single,double_toggle
#   Turn ON relay 1 on single click: EweAddBinding 5AD9E316_1_1_single_1
#   Turn OFF relay 2 on double click: EweAddBinding 5AD9E316_2_2_double_0

# Add a dimmer binding
EweAddBinding <deviceId>_<button>_<channel>_<actions>_dimmer_<step>_<min>_<max>
# Example: EweAddBinding 5AD9E316_1_0_hold_dimmer_20_10_100

# Remove a binding
EweRemoveBinding <deviceId>_<button>_<relay>
# Example: EweRemoveBinding 5AD9E316_1_1
```

#### MQTT Configuration
```
# Configure MQTT topic format
EweTopicMode <mode> [template]

# Available modes:
# mode = 0: Standard Tasmota format (default)
# mode = 1: Simplified format %prefix%/tasmota_ble/<deviceId>
# mode = 2: Format with type %prefix%/ewelink_<type>/<deviceId>
# mode = 3: Custom format (requires template)

# Available template variables:
# %prefix% : Tasmota prefix (tele, stat, cmnd)
# %topic% : Configured Tasmota topic
# %deviceid% : Remote ID
# %type% : Remote type
# %mac% : Full MAC address
# %shortmac% : Last 6 characters of MAC
# %alias% : Remote alias (if set, otherwise deviceId)

# Example with custom template:
EweTopicMode 3 %prefix%/custom/%deviceid%/%type%

# Example with custom template using alias:
EweTopicMode 3 %prefix%/remote/%alias%/%type%
```

#### Usage Statistics
```
# Enable/disable statistics
EweStats ON    # Enable statistics
EweStats OFF   # Disable statistics
EweStats       # Show current state

# Display button statistics
EweShowStats <deviceId>_<button>
# Example: EweShowStats 5AD9E316_1

# Response (JSON format):
{
    "total": 42,
    "first_used": "2024-03-16 08:45:24",
    "last_used": "2024-03-16 09:12:04",
    "actions": {
        "single": 30,
        "double": 10,
        "hold": 2
    },
    "hourly": [0,0,0,5,10,15,12,0,...],  # 24h distribution
    "daily": [10,15,5,2,5,3,2]           # 7-day distribution
}
```
**Note**: Statistics are disabled by default to save memory. Use `EweStats ON` to enable them.

#### Home Assistant MQTT Autodiscovery
```
# Enable/disable Home Assistant autodiscovery
EweHADiscovery ON    # Enable autodiscovery and publish config for all registered devices
EweHADiscovery OFF   # Disable autodiscovery and remove all device configs
EweHADiscovery       # Show current state

# Set custom discovery prefix (default: homeassistant)
EweHAPrefix <prefix>
# Example: EweHAPrefix homeassistant
EweHAPrefix          # Show current prefix
```

When enabled, each registered remote will automatically create entities in Home Assistant:
- **Event entities** for each button action (single, double, hold)
- **Signal sensor** showing the BLE signal strength in dBm

The entities will appear in Home Assistant with:
- Device name: `eWeLink <type> <alias or deviceId>`
- Manufacturer: eWeLink
- Model: S-MATE2 or R5
- Linked to your Tasmota device

**Setup Steps**:
1. Add and configure your remotes using `EweAddDevice`
2. Set aliases if desired using `EweAlias`
3. Enable autodiscovery with `EweHADiscovery ON`
4. Devices will appear automatically in Home Assistant

**Note**: Autodiscovery is disabled by default. When you enable it with `EweHADiscovery ON`, it will automatically publish the configuration for all registered devices. When you disable it with `EweHADiscovery OFF`, it will remove all device configurations from Home Assistant.

### MQTT Messages

Each button press sends an MQTT message:

```json
{
  "Button1": {
    "Action": "single"
  },
  "Signal": -90,
  "DeviceId": "5AD9E316",
  "DeviceType": "S-MATE2",
  "Sequence": 73,
  "Timestamp": 1741982724
}
```

### Auto-Update System

The module includes an automatic update system that can check and install new versions.

#### Update Commands

```
# Check for available updates
EweCheckUpdate

# Response (JSON format):
{
    "ewe_remote.be": {
        "current": "0.3.0",
        "new": "0.3.1",
        "update": true
    },
    "ewe_remote_dimmer.be": {
        "current": "0.2.0",
        "new": "0.2.0",
        "update": false
    }
}

# Install available updates
EweUpdate

# Manage automatic updates
EweAutoUpdate ON/1    # Enable daily check
EweAutoUpdate OFF/0   # Disable automatic check
EweAutoUpdate         # Show current status
```

#### Features

- Updates are checked daily at midnight when enabled
- Automatic update status is saved in `ewe_config.json`
- The ESP32 automatically restarts after a successful update
- The configuration is preserved during updates

#### Requirements

- Active internet connection
- Files are downloaded from the main GitHub repository
- The update system manages both `ewe_remote.be` and `ewe_remote_dimmer.be`

## Technical Information

- Bluetooth range: ~10 meters in open field
- LED on remote indicates button press
- Button press history kept for 1 hour in web interface
- Configuration saved in `ewe_config.json`
- Compatible with remotes:
  - S-MATE2 (3 buttons)
  - R5 (6 buttons)

## Troubleshooting

To manually test packet reception, use the Berry console:

```berry
# Test packet decoding
var test_packet = bytes('0201021B05FFFFEE1BC878F64A4790365AD509227B7442C5245C7DE4828B98')
var result = ewe.test_button(test_packet)
print(result)

# Test complete chain
ewe.parse(test_packet, -90, "S-MATE2", 1)
```
