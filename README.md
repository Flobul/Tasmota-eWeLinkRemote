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
   - Download the `remote.be` file
   - Copy it to your ESP32 via Tasmota web interface (Console -> Manage File System)
   - Enable it:
   ```
   br load('remote.be')
   ```

#### Automatic installation 
   - Paste this code in your ESP32 via Tasmota web interface (Console -> Berry Scripting Console)
   ```
  import path
  def start_eweremote_setup()
    var cl = webclient()
    var url = 'https://raw.githubusercontent.com/Flobul/Tasmota-eWeLinkRemote/main/remote.be'
    cl.begin(url)
    var r = cl.GET()
    if r != 200
      print('error getting remote.be')
      return false
    end
    var s = cl.get_string()
    cl.close()
    var f = open('remote.be', 'w')
    f.write(s)
    f.close()
    load('remote.be')
  end
   ```
start_eweremote_setup()

## Configuration

### Web Interface

The module adds a new "eWeLink Remote" button to Tasmota's main menu.

#### Adding a Remote

1. Press any button on the remote
2. The remote appears in the interface
3. Click "Save Device" to register it

#### Button Configuration

For each button, you can configure:
- The relay to control (dropdown list)
- Actions that will trigger the relay:
  - Single: single click
  - Double: double click
  - Hold: long press
- Click "Add" to create the binding

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
# Add a binding
EweAddBinding <deviceId>_<button>_<relay>_<actions>
# Example: EweAddBinding 5AD9E316_1_1_single,double

# Remove a binding
EweRemoveBinding <deviceId>_<button>_<relay>
# Example: EweRemoveBinding 5AD9E316_1_1
```

#### MQTT Configuration

```
# Configure MQTT topic format
EweTopic <mode>
# mode = 0: Standard Tasmota format (default)
# mode = 1: Simplified format tele/tasmota_ble/<deviceId>
```

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