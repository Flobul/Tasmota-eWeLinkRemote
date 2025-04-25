# eWeLink Remote Module for Tasmota

## Description

This module enables the use of eWeLink BLE remotes (SNZB-01P and R5) with Tasmota. It provides a web interface to easily configure the associations between remote buttons and Tasmota relays.

## Installation

### Prerequisites:
   - ESP32 with Tasmota installed
   - Berry activated
   - Tasmota Mi32-bluetooth version
   - Bluetooth enabled in Tasmota:
   ```
   SetOption115 1
   ```

### Module installation:

#### Manual installation 
   - Download the `remote.be` file or `remote_dimmer.be`
   - Copy it to your ESP32 via Tasmota web interface (Console -> Manage File System)
   - Enable it:
   ```
   br load('remote.be') # or remote_dimmer.be
   ```

#### Automatic installation 
   - Paste this code in your ESP32 via Tasmota web interface (Console -> Berry Scripting Console)
   ```
   import path
   
   def download_file(url, filename)
     var cl = webclient()
     cl.begin(url)
     var r = cl.GET()
     if r != 200
       print('error getting ' + filename)
       return false
     end
     var s = cl.get_string()
     cl.close()
     var f = open(filename, 'w')
     f.write(s)
     f.close()
     return true
   end
   
   def start_eweremote_setup()
     var remote_url = 'https://raw.githubusercontent.com/Flobul/Tasmota-eWeLinkRemote/main/remote.be' # or remote_dimmer.be
     var config_url = 'https://raw.githubusercontent.com/Flobul/Tasmota-eWeLinkRemote/main/ewe_config.json'
   
     if !download_file(remote_url, 'remote.be') # or remote_dimmer.be
       return false
     end
   
     if !download_file(config_url, 'ewe_config.json')
       return false
     end
   
     load('remote.be') # or remote_dimmer.be
   end
   
   start_eweremote_setup()
   ```
### Load on boot

If you would like a fully berry solution to loading eWeLinkRemote, add the following line to autoexec.be

   ```
    tasmota.add_rule('System#Boot', / -> tasmota.set_timer(10000, / -> load('remote.be'))) # or remote_dimmer.be
   ```

Otherwise, you can simply make a rule:

   ```
    Rule1 ON System#Boot DO backlog delay 20; br load('remote.be') ENDON # or remote_dimmer.be
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
```

#### Binding Management

```
# Add a relay binding
EweAddBinding <deviceId>_<button>_<relay>_<actions>_relay
# Example: EweAddBinding 5AD9E316_1_1_single,double_relay

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

# Example with custom template:
EweTopicMode 3 %prefix%/custom/%deviceid%/%type%
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

### MQTT Messages

Each button press sends an MQTT message:

```json
{
  "Button1": {
    "Action": "simple"
  },
  "Signal": -90,
  "DeviceType": "S-MATE2",
  "Sequence": 73,
  "Timestamp": 1741982724
}
```

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
