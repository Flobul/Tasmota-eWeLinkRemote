# This code is for the eWeLink BLE remote control
# Created by @Flobul on 2025-03-10
# Modified by @Flobul on 2025-04-24
#     Add support for dimmer lights
# Modified by @Flobul on 2025-05-01
# Version 0.3.0

import string
import json
import mqtt

class State
    var button
    var deviceId
    var type
    var signal
    var action
    var seq
    var time
    
    def init()
        self.button = -1
        self.deviceId = -1
        self.type = ''
        self.signal = -1
        self.action = ''
        self.seq = 0
        self.time = 0
    end
end
cbuf = bytes(-64)

var g_state = State()

var col_background = tasmota.webcolor(2)            # Background color of cards
var col_button = tasmota.webcolor(10)               # Menu button color
var col_button_hover = tasmota.webcolor(11)         # Menu button hover color
var col_button_delete = tasmota.webcolor(12)        # Delete button color
var col_button_delete_hover = tasmota.webcolor(13)  # Delete button hover color
var col_button_success = tasmota.webcolor(14)       # Success button color
var col_button_success_hover = tasmota.webcolor(15) # Success button hover color

def getmac(cter)
    var mac = tasmota.wifi()['mac']
    if mac == ""
        mac = tasmota.eth()['mac']
    end
    mac = string.replace(mac, ":", "")
    if cter > 0 && size(mac) > cter
        mac = mac[size(mac) - cter .. size(mac) - 1]
    end
    return mac
end

class ewe_helpers
    static def read_config()
        var default_config = {
            'devices': {},
            'mqtt': {
                'topic_mode': 0,
                'topic_template': ''
            },
            'settings': {
                'stats_enabled': false
            }
        }
        
        try
            var f = open("ewe_config.json", "r")
            var config = json.load(f.read())
            f.close()
            return config
        except .. 
            ewe_helpers.write_config(default_config)
            return default_config
        end
    end

    static def write_config(config)
        var f = open("ewe_config.json", "w")
        f.write(json.dump(config))
        f.close()
    end

    static def add_device(deviceId)
        var config = ewe_helpers.read_config()
        if !config['devices'] config['devices'] = {} end
        var devType = g_state.type
        if !devType devType = 'R5' end
        config['devices'][deviceId] = {
            'added_at': tasmota.rtc()['local'],
            'bindings': {},
            'type': devType
        }
        ewe_helpers.write_config(config)
    end

    static def set_topic_config(mode, template)
        var config = ewe_helpers.read_config()
        if !config['mqtt'] config['mqtt'] = {} end
        config['mqtt']['topic_mode'] = mode
        config['mqtt']['topic_template'] = template ? template : ''
        ewe_helpers.write_config(config)
    end
    
    static def get_topic_config()
        var config = ewe_helpers.read_config()
        if !config['mqtt'] return {'mode': 0, 'template': ''} end
        return {
            'mode': config['mqtt'].find('topic_mode', 0),
            'template': config['mqtt'].find('topic_template', '')
        }
    end

    static def remove_device(deviceId)
        var config = ewe_helpers.read_config()
        if !config['devices'] return false end
        if !config['devices'].contains(deviceId) return false end
        
        config['devices'].remove(deviceId)
        ewe_helpers.write_config(config)
        return true
    end

    static def is_device_registered(deviceId)
        var config = ewe_helpers.read_config()
        return config['devices'] && config['devices'].contains(deviceId)
    end

    static def get_button_bindings(deviceId, button)
        var config = ewe_helpers.read_config()
        if !config['devices'] || !config['devices'].contains(deviceId) return [] end
        
        var device = config['devices'][deviceId]
        if !device.contains('bindings') return [] end
        
        var button_key = 'button' + str(button)
        if !device['bindings'].contains(button_key) return [] end
        
        return device['bindings'][button_key]
    end

    static def add_binding(deviceId, button, relay, actions, output_type, dimmer_params)
        var config = ewe_helpers.read_config()
        if !config['devices'] || !config['devices'].contains(deviceId) return false end
        
        var device = config['devices'][deviceId]
        if !device.contains('bindings')
            device['bindings'] = {}
        end
        
        var button_key = 'button' + str(button)
        if !device['bindings'].contains(button_key)
            device['bindings'][button_key] = []
        end
        
        if output_type == 'dimmer'
            dimmer_params = ewe_helpers.validate_dimmer_params(dimmer_params)
        end
        
        var binding = {
            'relay': relay,
            'actions': actions,
            'output_type': output_type,
            'dimmer_params': dimmer_params,
            'dimmer_direction': 'up',
            'last_value': 0,
            'last_action': ''
        }
        
        device['bindings'][button_key].push(binding)
        
        print(format('DBG: Added binding with params: %s', json.dump(dimmer_params)))
        
        ewe_helpers.write_config(config)
        return true
    end

    static def remove_binding(deviceId, button, relay)
        var config = ewe_helpers.read_config()
        if !config['devices'] || !config['devices'].contains(deviceId) return false end
        
        var device = config['devices'][deviceId]
        if !device.contains('bindings') return false end
        
        var button_key = 'button' + str(button)
        if !device['bindings'].contains(button_key) return false end
        
        var bindings = device['bindings'][button_key]
        var idx = -1
        for i: 0..size(bindings)-1
            if bindings[i]['relay'] == relay
                idx = i
                break
            end
        end
        
        if idx >= 0
            bindings.remove(idx)
            ewe_helpers.write_config(config)
            return true
        end
        return false
    end

    static def set_stats_enabled(enabled)
        var config = ewe_helpers.read_config()
        if !config['settings'] config['settings'] = {} end
        config['settings']['stats_enabled'] = enabled
        ewe_helpers.write_config(config)
    end
    
    static def is_stats_enabled()
        var config = ewe_helpers.read_config()
        if !config['settings'] return false end
        return config['settings'].find('stats_enabled', false)
    end
        
    static def update_stats(deviceId, button, action)
        if !ewe_helpers.is_stats_enabled() return end
        
        var config = ewe_helpers.read_config()
        if !config.contains('stats') config['stats'] = {} end
        if !config['stats'].contains(deviceId) config['stats'][deviceId] = {} end
        
        var button_key = 'button' + str(button)
        if !config['stats'][deviceId].contains(button_key)
            var hourly = []
            var daily = []
            for i:0..23 hourly.push(0) end
            for i:0..6 daily.push(0) end
            
            config['stats'][deviceId][button_key] = {
                'total_clicks': 0,
                'first_used': tasmota.rtc()['local'],
                'last_used': tasmota.rtc()['local'],
                'actions': {},
                'hourly': hourly,
                'daily': daily
            }
        end
        
        var stats = config['stats'][deviceId][button_key]
        stats['total_clicks'] += 1
        stats['last_used'] = tasmota.rtc()['local']
        
        if !stats['actions'].contains(action) stats['actions'][action] = 0 end
        stats['actions'][action] += 1
        
        var hour = int(tasmota.strftime('%H', tasmota.rtc()['local']))
        var day = int(tasmota.strftime('%w', tasmota.rtc()['local']))
        if hour >= 0 && hour < 24 stats['hourly'][hour] += 1 end
        if day >= 0 && day < 7 stats['daily'][day] += 1 end
        
        ewe_helpers.write_config(config)
    end

    static def get_stats(deviceId, button)
        if !ewe_helpers.is_stats_enabled()
            return {'error': 'Statistics are disabled. Use EweStats ON to enable them'}
        end
        
        var config = ewe_helpers.read_config()
        if !config.contains('stats') return nil end
        if !config['stats'].contains(deviceId) return nil end
        
        var button_key = 'button' + str(button)
        if !config['stats'][deviceId].contains(button_key) return nil end
        
        return config['stats'][deviceId][button_key]
    end

    static def validate_dimmer_params(params)
        if type(params) != 'map'
            params = {}
        end
        
        params['max'] = 100
        params['min'] = params.find('min', 0) < 0 ? 0 : params.find('min', 0)
        params['step'] = params.find('step', 20) < 1 ? 20 : params.find('step', 20)
        
        return params
    end
end

class ewe_remote : Driver
    static XOR_TABLE = [
        15, 57, 190, 95, 39, 5, 190, 249, 102, 181, 116,
        13, 4, 134, 210, 97, 85, 187, 252, 22, 52, 64,
        126, 29, 56, 110, 228, 6, 170, 121, 50, 149, 102,
        181, 116, 13, 219, 140, 233, 1, 42
    ]
    static button_actions = ['single', 'double', 'hold']
    static types = {0x46: "S-MATE2", 0x47: "R5"}
    var last_data
    var button_history
    var dimmer_states

    def init()
        import BLE
        import cb
        var cbp = cb.gen_cb(/svc,manu->self.ble_cb(svc,manu))
        BLE.adv_cb(cbp,cbuf)
        self.last_data = bytes('')
        self.button_history = {}
        self.dimmer_states = {}
        tasmota.add_fast_loop(/-> BLE.loop())
    end

    def get_dimmer_state(deviceId, button, relay)
        var key = format("%s_%d_%d", deviceId, button, relay)
        if !self.dimmer_states.contains(key)
            self.dimmer_states[key] = {
                'direction': 'up',
                'last_value': 0,
                'last_time': 0
            }
        end
        return self.dimmer_states[key]
    end

    def xor_decrypt(encrypted, seed)
        if size(encrypted) == 0 return [] end
        var result = []
        var table_length = size(self.XOR_TABLE)
        for i: 0..size(encrypted)-1
            var key = self.XOR_TABLE[i % table_length] ^ seed
            result.push(encrypted[i] ^ key)
        end
        return result
    end

    def get_mqtt_topic(device_id)
        var config = ewe_helpers.get_topic_config()
        var mode = config['mode']
        var template = config['template']
        var prefix = tasmota.cmd('Prefix', true)['Prefix3']
        
        if mode == 0
            var macFormatted = getmac(6)
            var fullTopic = string.replace(string.replace(
                tasmota.cmd('FullTopic', true)['FullTopic'],
                '%topic%', tasmota.cmd('Topic', true)['Topic']),
                '%prefix%', prefix)
            return string.replace(fullTopic, '%06X', macFormatted) + 'SWITCH'
        elif mode == 1
            return format("%s/tasmota_ble/%s", prefix, device_id)
        elif mode == 2
            return format("%s/ewelink_%s/%s", prefix, g_state.type.tolower(), device_id)
        elif mode == 3 && template != ''
            var replacements = {
                '%prefix%': prefix,
                '%topic%': tasmota.cmd('Topic', true)['Topic'],
                '%deviceid%': device_id,
                '%type%': g_state.type,
                '%mac%': getmac(0),
                '%shortmac%': getmac(6)
            }
            var result = template
            for key: replacements.keys()
                result = string.replace(result, key, replacements[key])
            end
            return result
        end
        return format("%s/tasmota_ble/%s", prefix, device_id)
    end

    def test_button(d)
        if size(d) < 31 return nil end
        
        var seed = d[20]
        var encrypted = []
        for i: 21..30 encrypted.push(d[i]) end
        
        var decrypted = self.xor_decrypt(encrypted, seed)
        if size(decrypted) < 9 return nil end

        return {
            'button': decrypted[1] + 1,
            'action': self.button_actions[decrypted[2]],
            'counter': decrypted[8],
            'device_id': string.format("%02X%02X%02X%02X",
                d[16], d[17], d[18], d[19])
        }
    end

    def ble_cb(svc,manu)
        if cbuf[0..5] != bytes("665544332211") return end
        var payload = cbuf[9..(cbuf[8]+8)]
        if payload == self.last_data return end

        self.last_data = payload
        self.parse(payload, (255 - cbuf[7]) * -1, self.types[cbuf[22]], cbuf[24])
    end

    def handle_dimmer(binding, result, current_value, dimmer_params)
        var state = self.get_dimmer_state(result['device_id'], result['button'], binding['relay'])
        var current_time = tasmota.rtc()['local']
        
        var dimmer_cmd = 'Dimmer'
        if tasmota.cmd('SetOption37', true)['SetOption37'] >= 128 && dimmer_params.contains('channel')
            dimmer_cmd = 'Dimmer' + str(dimmer_params['channel'])
        end
        
        if result['action'] == 'single'
            if current_value <= dimmer_params['min']
                tasmota.cmd(format('%s %d', dimmer_cmd, dimmer_params['max']))
            else
                tasmota.cmd(format('%s %d', dimmer_cmd, dimmer_params['min']))
            end
            state['direction'] = 'up'
        elif result['action'] == 'double'
            tasmota.cmd(format('%s %d', dimmer_cmd, dimmer_params['max']))
            state['direction'] = 'up'
        elif result['action'] == 'hold'
            if (current_time - state['last_time']) > 1
                if current_value >= dimmer_params['max']
                    state['direction'] = 'down'
                elif current_value <= dimmer_params['min']
                    state['direction'] = 'up'
                end
            else
                if current_value >= dimmer_params['max'] && state['direction'] == 'up'
                    print('DBG: reached max, changing direction to down')
                    state['direction'] = 'down'
                elif current_value <= dimmer_params['min'] && state['direction'] == 'down'
                    print('DBG: reached min, changing direction to up')
                    state['direction'] = 'up'
                end
            end
    
            print(format('DBG: hold - moving dimmer %s (current: %d, last: %d, step: %d)', 
                state['direction'], current_value, state['last_value'], dimmer_params['step']))
    
            var new_value
            if state['direction'] == 'up'
                new_value = current_value + dimmer_params['step']
                if new_value > dimmer_params['max']
                    new_value = dimmer_params['max']
                end
            else
                new_value = current_value - dimmer_params['step']
                if new_value < dimmer_params['min']
                    new_value = dimmer_params['min']
                end
            end
    
            state['last_value'] = current_value
            state['last_time'] = current_time
    
            if new_value != current_value
                tasmota.cmd(format('%s %d', dimmer_cmd, new_value))
            end
        end
        
        if result['action'] != 'hold' && binding.contains('last_action') && binding['last_action'] == 'hold'
            tasmota.cmd(format('%s %d', dimmer_cmd, current_value))
        end
        
        binding['last_action'] = result['action']
    end

    def parse(d, RSSI, device_type, sequence)
        var result = self.test_button(d)
        if !result return end

        ewe_helpers.update_stats(result['device_id'], result['button'], result['action'])

        var timestamp = tasmota.rtc()['local']
        
        g_state.button = result['button']
        g_state.action = result['action']
        g_state.deviceId = result['device_id']
        g_state.type = device_type
        g_state.signal = RSSI
        g_state.seq = sequence
        g_state.time = timestamp

        var bindings = ewe_helpers.get_button_bindings(result['device_id'], result['button'])
        if size(bindings) > 0
            var power = tasmota.get_power()
            if power != nil
                for binding: bindings
                    if binding['actions'].find(result['action']) != nil
                        var output_type = binding.find('output_type', 'relay')
                        if output_type == 'relay'
                            if binding['relay'] <= size(power)
                                tasmota.cmd(format('Power%d toggle', binding['relay']))
                            end
                        elif output_type == 'dimmer'
                            if !binding.contains('dimmer_params')
                                binding['dimmer_params'] = {'step': 20, 'min': 0, 'max': 100}
                            end
                            var dimmer_params = binding['dimmer_params']
                            
                            dimmer_params['max'] = 100
                            if dimmer_params['min'] < 0 dimmer_params['min'] = 0 end
                            if dimmer_params['step'] < 1 || dimmer_params['step'] > 50 dimmer_params['step'] = 20 end
                            
                            print(format('DBG: Using dimmer params: %s', json.dump(dimmer_params)))

                            var current_value = 0
                            
                            try
                                var dimmer_response = tasmota.cmd('Dimmer', true)
                                if type(dimmer_response) == 'instance'
                                    current_value = dimmer_response['Dimmer']
                                    print(format('DBG: current dimmer: %d', current_value))
                                end
                                
                            except .. as e
                                print(format('ERR: unable to get values: %s', str(e)))
                            end
                            
                            self.handle_dimmer(binding, result, current_value, dimmer_params)

                            var config = ewe_helpers.read_config()
                            if config['devices'] && config['devices'].contains(result['device_id'])
                                var button_key = 'button' + str(result['button'])
                                if config['devices'][result['device_id']]['bindings'].contains(button_key)
                                    var device_bindings = config['devices'][result['device_id']]['bindings'][button_key]
                                    for i:0..size(device_bindings)-1
                                        if device_bindings[i]['relay'] == binding['relay']
                                            device_bindings[i] = binding
                                            break
                                        end
                                    end
                                    ewe_helpers.write_config(config)
                                end
                            end
                        end
                    end
                end
            end
        end

        var msg = format(
            '{\"Button%d\":{\"Action\":\"%s\"},\"Signal\":%d,\"DeviceType\":\"%s\",\"Sequence\":%d,\"Timestamp\":%d}',
            result['button'], result['action'], RSSI, device_type, sequence, timestamp
        )
        mqtt.publish(self.get_mqtt_topic(result['device_id']), msg)

        tasmota.cmd(format("Event Button%d_%s", result['button'], result['action']))
    end

    def web_sensor()
        if g_state.button == -1 return nil end

        var deviceId = g_state.deviceId
        var isRegistered = ewe_helpers.is_device_registered(deviceId)
        var current_time = tasmota.rtc()['local']

        if !self.button_history
            self.button_history = {}
        end

        if !self.button_history.contains(deviceId)
            self.button_history[deviceId] = {}
        end

        var button_key = str(g_state.button)
        self.button_history[deviceId][button_key] = {
            'button': g_state.button,
            'action': g_state.action,
            'signal': g_state.signal,
            'time': g_state.time,
            'type': g_state.type
        }

        var devices_to_remove = []
        for dev: self.button_history.keys()
            var buttons_to_remove = []
            for btn: self.button_history[dev].keys()
                if (current_time - self.button_history[dev][btn]['time']) > 3600
                    buttons_to_remove.push(btn)
                end
            end
            for btn: buttons_to_remove
                self.button_history[dev].remove(btn)
            end
            if size(self.button_history[dev]) == 0
                devices_to_remove.push(dev)
            end
        end
        for dev: devices_to_remove
            self.button_history.remove(dev)
        end

        var msg = ''
        for dev: self.button_history.keys()
            var isDevRegistered = ewe_helpers.is_device_registered(dev)
            var btnType = ''
            for btn: self.button_history[dev].keys()
                if self.button_history[dev][btn]['type'] != ''
                    btnType = self.button_history[dev][btn]['type']
                    break
                end
            end

            msg += format(
                '{s}REMOTE SWITCH (%s){m}%s{e}',
                btnType, dev
            )    

            for btn: self.button_history[dev].keys()
                var entry = self.button_history[dev][btn]
                msg += format(
                    '{s}Button{m}%d{e}' ..
                    '{s}Action{m}%s{e}' ..
                    '{s}Signal{m}%d dBm{e}' ..
                    '{s}Time{m}%s{e}',
                    entry['button'],
                    entry['action'],
                    entry['signal'],
                    tasmota.strftime("%H:%M:%S", entry['time'])
                )
            end

            if isDevRegistered
                msg += format(
                    '{s}<button style="margin:1px;background-color: %s; color: white; border:0; border-radius:0.3rem; padding:5px 10px; cursor:pointer; transition-duration:0.4s" ' ..
                    'onmouseover="this.style.backgroundColor=\'%s\'" ' ..
                    'onmouseout="this.style.backgroundColor=\'%s\'" ' ..
                    'onclick="fetch(\'cm?cmnd=EweRemoveDevice %s\')">Remove Device</button>{e}',
                    col_button_delete, col_button_delete_hover, col_button_delete, dev
                )
            else
                msg += format(
                    '{s}<button style="margin:1px;background-color: %s; color: white; border:0; border-radius:0.3rem; padding:5px 10px; cursor:pointer; transition-duration:0.4s" ' ..
                    'onmouseover="this.style.backgroundColor=\'%s\'" ' ..
                    'onmouseout="this.style.backgroundColor=\'%s\'" ' ..
                    'onclick="fetch(\'cm?cmnd=EweAddDevice %s\')">Save Device</button>{e}',
                    col_button_success, col_button_success_hover, col_button_success, dev
                )
            end
            msg += '{s}<hr>{m}<hr>{e}'
        end

        if msg != ''
            tasmota.web_send(msg)
        end
    end

    def web_add_main_button()
        import webserver
        webserver.content_send(
            "<form id=but_ewe style='display: block;' action='ewe' method='get'>" ..
            "<button style='background-color:" + col_button + "; color:white; border:0; border-radius:0.3rem; " ..
            "padding:5px 10px; cursor:pointer; transition-duration:0.4s' " ..
            "onmouseover='this.style.backgroundColor=\"" + col_button_hover + "\"' " ..
            "onmouseout='this.style.backgroundColor=\"" + col_button + "\"'>eWeLink Remote</button></form>"
        )
    end

    def page_ewe()
        import webserver
        if !webserver.check_privileged_access() return nil end
        
        webserver.content_start("Remote Configuration")
        webserver.content_send_style()
        
        var config = ewe_helpers.read_config()
        if !config return nil end

        var setoption37 = 0
        try
            var so = tasmota.cmd('SetOption37', true)
            if type(so) == 'instance'
                setoption37 = so['SetOption37']
                print(format('DBG: current setoption37: %d', setoption37))
            end
        except .. 
            print('DBG: Error getting SetOption37')
        end

        var devices = config.find('devices', {})
        if size(devices) == 0
            webserver.content_send('<p style="text-align:center">No devices registered</p>')
            webserver.content_button(webserver.BUTTON_MAIN)
            webserver.content_stop()
            return
        end

        var power = tasmota.get_power()
        var power_count = power ? size(power) : 0
        
        for deviceId: devices.keys()
            var device = devices[deviceId]
            if !device continue end

            var device_type = device.find('type', 'R5')
            var num_buttons = device_type == 'S-MATE2' ? 3 : 6

            webserver.content_send(format(
                '<fieldset class="card" style="background-color: %s;">' ..
                '<legend><b>Remote %s (%s)</b></legend>',
                col_background, deviceId, device_type
            ))

            for btn: 1..num_buttons
                webserver.content_send(format(
                    '<div style="background:rgba(0,0,0,0.05)">' ..
                    '<div>Button %d</div>',
                    btn
                ))
                
                var current_bindings = device.find('bindings', {})
                var button_key = 'button' + str(btn)
                
                if current_bindings.contains(button_key)
                    var bindings = current_bindings[button_key]
                    for binding: bindings
                        var output_text = binding['output_type'] == 'relay' ? 
                            format('Relay %d', binding['relay']) :
                            format('Dimmer %d [%d-%d step:%d]', 
                                binding['relay'],
                                binding['dimmer_params']['min'],
                                binding['dimmer_params']['max'],
                                binding['dimmer_params']['step']
                            )
                        webserver.content_send(format(
                            '<div style="background:%s; color:white; border-radius:3px; display:inline-flex; justify-content:space-between; align-items:center; transition-duration:0.4s" ' ..
                            'onmouseover="this.style.backgroundColor=\'%s\'" ' ..
                            'onmouseout="this.style.backgroundColor=\'%s\'">' ..
                            '<span>%s [%s]</span>' ..
                            '<button onclick="fetch(\'cm?cmnd=EweRemoveBinding %s_%d_%d\').then(()=>window.location.reload())" ' ..
                            'style="background:none; border:none; color:white; cursor:pointer;width: 20px">' ..
                            '×</button>' ..
                            '</div>',
                            col_button_success,
                            col_button_delete,
                            col_button_success,
                            output_text,
                            binding['actions'].concat(','),
                            deviceId, btn, binding['relay']
                        ))
                    end
                end
                if power_count > 0
                    webserver.content_send(
                        '<div>' ..
                        '<select id="output_type' + str(btn) + '_' + deviceId + '" style="width:100px" ' ..
                        'onchange="(function(e){' ..
                        'var isDimmer = e.target.value === \'dimmer\';' ..
                        'var dimmerParams = document.getElementById(\'dimmer_params' + str(btn) + '_' + deviceId + '\');' ..
                        'if (dimmerParams) dimmerParams.style.display = isDimmer ? \'inline-block\' : \'none\';' ..
                        'document.getElementById(\'single' + str(btn) + '_' + deviceId + '\').checked = !isDimmer;' ..
                        'document.getElementById(\'hold' + str(btn) + '_' + deviceId + '\').checked = isDimmer;' ..
                        'var relaySelect = document.getElementById(\'relay_select' + str(btn) + '_' + deviceId + '\');' ..
                        'var channelSelect = document.getElementById(\'channel_select' + str(btn) + '_' + deviceId + '\');' ..
                        'if (relaySelect) relaySelect.style.display = !isDimmer ? \'inline-block\' : \'none\';' ..
                        'if (channelSelect) channelSelect.style.display = isDimmer ? \'inline-block\' : \'none\';' ..
                        '})(event)\">' ..
                        '<option value="relay">Relay</option>' ..
                        '<option value="dimmer">Dimmer</option>' ..
                        '</select> => '
                    )
                    
                    webserver.content_send(
                        '<span id="relay_select' + str(btn) + '_' + deviceId + '" style="display:inline-block">' ..
                        '<select id="relay' + str(btn) + '_' + deviceId + '">'
                    )
                    for relay: 1..power_count
                        webserver.content_send(format(
                            '<option value="%d">Output %d</option>',
                            relay, relay
                        ))
                    end
                    webserver.content_send('</select></span>')
            
                    webserver.content_send(
                        '<span id="channel_select' + str(btn) + '_' + deviceId + '" style="display:none">' ..
                        '<select id="channel' + str(btn) + '_' + deviceId + '">' ..
                        '<option value="0">All channels</option>' ..
                        (setoption37 >= 128 ? 
                            '<option value="1">RGB channels</option>' ..
                            '<option value="2">White channels</option>' ..
                            '<option value="4">Linked lights</option>' 
                            : '') ..
                        '</select></span><br>'
                    )
            
                    webserver.content_send(
                        '<label style="padding:10px;"><input type="checkbox" id="single' + str(btn) + '_' + deviceId + '" checked> Single</label>' ..
                        '<label style="padding:10px;"><input type="checkbox" id="double' + str(btn) + '_' + deviceId + '"> Double</label>' ..
                        '<label style="padding:10px;"><input type="checkbox" id="hold' + str(btn) + '_' + deviceId + '"> Hold</label>' ..
                        '<br><span id="dimmer_params' + str(btn) + '_' + deviceId + '" style="display:none; margin-left:5px">' ..
                        'Step: <input type="number" id="step' + str(btn) + '_' + deviceId + '" value="20" min="1" max="100" style="width:60px">' ..
                        ' Min: <input type="number" id="min' + str(btn) + '_' + deviceId + '" value="10" min="10" max="1000" style="width:70px">' ..
                        ' Max: <input type="number" id="max' + str(btn) + '_' + deviceId + '" value="100" min="0" max="1000" style="width:70px">' ..
                        '</span>' ..
                        '<button onclick="addBinding(\'' + deviceId + '\',' + str(btn) + ')">Add</button>'
                    )
            
                    webserver.content_send('</div>')
                end
            end
            
            webserver.content_send(format(
                '<div style="text-align:right; margin-top:10px">' ..
                '<button onclick="if(confirm(\'Remove this remote?\')) fetch(\'cm?cmnd=EweRemoveDevice %s\').then(()=>window.location.reload())" ' ..
                'style="background:%s; color:white; border:none; padding:5px 10px; border-radius:3px; cursor:pointer; transition-duration:0.4s" ' ..
                'onmouseover="this.style.backgroundColor=\'%s\'" ' ..
                'onmouseout="this.style.backgroundColor=\'%s\'">Remove Device</button>' ..
                '</div>' ..
                '</fieldset>',
                deviceId, col_button_delete, col_button_delete_hover, col_button_delete
            ))
        end
        
        webserver.content_send(
            '<script>' ..
            'function addBinding(deviceId, btn) {' ..
            '  const output_type = document.getElementById("output_type"+btn+"_"+deviceId).value;' ..
            '  var relay = "0";' ..
            '  if (output_type === "relay") {' ..
            '    relay = document.getElementById("relay"+btn+"_"+deviceId).value;' ..
            '  } else {' ..
            '    var channelSelect = document.getElementById("channel"+btn+"_"+deviceId);' ..
            '    if (channelSelect) {' ..
            '      relay = channelSelect.value;' ..
            '    }' ..
            '  }' ..
            '  const actions = [];' ..
            '  if(document.getElementById("single"+btn+"_"+deviceId).checked) actions.push("single");' ..
            '  if(document.getElementById("double"+btn+"_"+deviceId).checked) actions.push("double");' ..
            '  if(document.getElementById("hold"+btn+"_"+deviceId).checked) actions.push("hold");' ..
            '  if(actions.length === 0) {' ..
            '    alert("Please select at least one action");' ..
            '    return;' ..
            '  }' ..
            '  let command = deviceId+"_"+btn+"_"+relay+"_"+actions.join(",")+"_"+output_type;' ..
            '  if(output_type === "dimmer") {' ..
            '    const step = document.getElementById("step"+btn+"_"+deviceId).value;' ..
            '    const min = document.getElementById("min"+btn+"_"+deviceId).value;' ..
            '    const max = document.getElementById("max"+btn+"_"+deviceId).value;' ..
            '    command += "_"+step+"_"+min+"_"+max;' ..
            '  }' ..
            '  fetch("cm?cmnd=EweAddBinding "+command)' ..
            '    .then(() => window.location.reload());' ..
            '}' ..
            '</script>'
        )
        
        webserver.content_button(webserver.BUTTON_MAIN)
        webserver.content_stop()
    end

    def web_add_handler()
        import webserver
        webserver.on("/ewe", / -> self.page_ewe(), webserver.HTTP_GET)
    end
end

def cmd_add_device(cmd, idx, payload, payload_json)
    var deviceId = payload
    if string.find(payload, '_') > 0
        deviceId = string.split(payload, '_')[1]
    end
    
    if deviceId == ''
        var config = ewe_helpers.read_config()
        if !config['devices'] || size(config['devices']) == 0
            tasmota.resp_cmnd_str('No devices registered')
            return
        end
        var devices = []
        for id: config['devices'].keys()
            var added_at = config['devices'][id]['added_at']
            devices.push(format("%s (added: %s)", id, tasmota.strftime("%Y-%m-%d %H:%M:%S", added_at)))
        end
        tasmota.resp_cmnd_str(json.dump(devices))
        return
    end
    
    deviceId = string.split(deviceId, '[^0-9A-Fa-f]')[0]
    
    ewe_helpers.add_device(deviceId)
    tasmota.resp_cmnd_str(deviceId)
end

def cmd_remove_device(cmd, idx, payload, payload_json)
    var deviceId = payload
    if deviceId == ''
        tasmota.resp_cmnd_str('Please specify device ID')
        return
    end
    
    if ewe_helpers.remove_device(deviceId)
        tasmota.resp_cmnd(string.format('{"%s": "Done"}', deviceId))
    else
        tasmota.resp_cmnd(string.format('{"%s": "Unknown"}', deviceId))
    end
end

def cmd_add_binding(cmd, idx, payload, payload_json)
    var parts = string.split(payload, '_')
    if size(parts) < 4
        tasmota.resp_cmnd_str('Invalid format. Use: deviceId_button_relay_actions_type[_step_min_max]')
        return
    end
    
    var deviceId = parts[0]
    var button = int(parts[1])
    var relay = int(parts[2])
    var actions = string.split(parts[3], ',')
    var output_type = 'relay'
    var dimmer_params = {'step': 20, 'min': 0, 'max': 100}
    
    if size(parts) >= 5
        output_type = parts[4]
        if output_type == 'dimmer' && size(parts) >= 8
            dimmer_params = {
                'step': int(parts[5]),
                'min': int(parts[6]),
                'max': int(parts[7])
            }
        end
    end
    
    if ewe_helpers.add_binding(deviceId, button, relay, actions, output_type, dimmer_params)
        tasmota.resp_cmnd_str('Binding added')
    else
        tasmota.resp_cmnd_failed()
    end
end

def cmd_remove_binding(cmd, idx, payload, payload_json)
    var parts = string.split(payload, '_')
    if size(parts) != 3
        tasmota.resp_cmnd_str('Invalid format. Use: deviceId_button_relay')
        return
    end
    
    var deviceId = parts[0]
    var button = int(parts[1])
    var relay = int(parts[2])
    
    if ewe_helpers.remove_binding(deviceId, button, relay)
        tasmota.resp_cmnd_str('Binding removed')
    else
        tasmota.resp_cmnd_failed()
    end
end

def cmd_set_topic_mode(cmd, idx, payload, payload_json)
    var parts = string.split(payload, ' ')
    var mode = 0
    var template = ''
    
    if size(parts) > 0
        mode = int(parts[0])
        if size(parts) > 1
            template = string.split(payload, ' ', 2)[1]
        end
    end
    
    if mode < 0 || mode > 3
        tasmota.resp_cmnd_str('Invalid mode (0-3)')
        return
    end
    
    if mode == 3 && template == ''
        tasmota.resp_cmnd_str('Template required for mode 3. Available variables: %prefix%, %topic%, %deviceid%, %type%, %mac%, %shortmac%')
        return
    end
    
    ewe_helpers.set_topic_config(mode, template)
    
    tasmota.resp_cmnd(format("{\"Mode\":%d,\"Template\":\"%s\"}", mode, template))
end

def cmd_show_stats(cmd, idx, payload, payload_json)
    var parts = string.split(payload, '_')
    if size(parts) != 2
        tasmota.resp_cmnd_str('Invalid format. Use: deviceId_button')
        return
    end
    
    var stats = ewe_helpers.get_stats(parts[0], int(parts[1]))
    if !stats
        tasmota.resp_cmnd_str('No statistics available')
        return
    end
    
    if stats.contains('error')
        tasmota.resp_cmnd_str(stats['error'])
        return
    end
    
    tasmota.resp_cmnd(format(
        "{\"total\":%d," ..
        "\"first_used\":\"%s\"," ..
        "\"last_used\":\"%s\"," ..
        "\"actions\":%s," ..
        "\"hourly\":%s," .. 
        "\"daily\":%s}",
        stats['total_clicks'],
        tasmota.strftime('%Y-%m-%d %H:%M:%S', stats['first_used']),
        tasmota.strftime('%Y-%m-%d %H:%M:%S', stats['last_used']),
        json.dump(stats['actions']),
        json.dump(stats['hourly']),
        json.dump(stats['daily'])
    ))
end

def cmd_set_stats(cmd, idx, payload, payload_json)
    if payload == ''
        var enabled = ewe_helpers.is_stats_enabled()
        tasmota.resp_cmnd_str(enabled ? 'ON' : 'OFF')
        return
    end
    
    var enabled = payload == '1' || payload.toupper() == 'ON'
    ewe_helpers.set_stats_enabled(enabled)
    tasmota.resp_cmnd_str(enabled ? 'ON' : 'OFF')
end

ewe = ewe_remote()
tasmota.add_driver(ewe)

tasmota.add_cmd('EweAddDevice', cmd_add_device)
tasmota.add_cmd('EweRemoveDevice', cmd_remove_device)
tasmota.add_cmd('EweTopicMode', cmd_set_topic_mode)
tasmota.add_cmd('EweAddBinding', cmd_add_binding)
tasmota.add_cmd('EweRemoveBinding', cmd_remove_binding)
tasmota.add_cmd('EweShowStats', cmd_show_stats)
tasmota.add_cmd('EweStats', cmd_set_stats)

ewe.web_add_handler()