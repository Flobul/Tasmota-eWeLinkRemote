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
        try
            var f = open("ewe_config.json", "r")
            var config = json.load(f.read())
            f.close()
            return config
        except .. 
            return {'devices':{}, 'topic_mode': 0}
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
        config['devices'][deviceId] = {
            'added_at': tasmota.rtc()['local'],
            'bindings': {}  # Initialisation des bindings à la création
        }
        ewe_helpers.write_config(config)
    end

    static def set_topic_mode(mode)
        var config = ewe_helpers.read_config()
        config['topic_mode'] = mode
        ewe_helpers.write_config(config)
    end

    static def get_topic_mode()
        var config = ewe_helpers.read_config()
        return config['topic_mode']
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

    static def set_relay_binding(deviceId, button, relay)
        var config = ewe_helpers.read_config()
        if !config['devices'] return false end
        if !config['devices'].contains(deviceId) return false end
        
        var device = config['devices'][deviceId]
        if !device.contains('bindings')
            device['bindings'] = {}  # Initialise si n'existe pas
        end
        
        device['bindings']['button' + str(button)] = relay
        ewe_helpers.write_config(config)
        return true
    end

    static def get_relay_binding(deviceId, button)
        var config = ewe_helpers.read_config()
        if !config['devices'] return nil end
        if !config['devices'].contains(deviceId) return nil end
        
        var device = config['devices'][deviceId]
        if !device.contains('bindings') 
            device['bindings'] = {}  # Initialise si n'existe pas
            ewe_helpers.write_config(config)
        end
        
        var button_key = 'button' + str(button)
        return device['bindings'].contains(button_key) ? device['bindings'][button_key] : nil
    end

    static def list_bindings()
        var config = ewe_helpers.read_config()
        var result = []
        if !config['devices'] return result end
        
        for deviceId: config['devices'].keys()
            var device = config['devices'][deviceId]
            if device.contains('bindings') && size(device['bindings']) > 0
                for button_key: device['bindings'].keys()
                    var relay = device['bindings'][button_key]
                    # Extrait le numéro du bouton de la clé (ex: 'button1' -> '1')
                    var button = string.split(button_key, 'button')[1]
                    result.push(format("Device %s: Button %s -> Relay %d", 
                                     deviceId, button, relay))
                end
            end
        end
        return result
    end
    static def remove_binding(deviceId, button)
        var config = ewe_helpers.read_config()
        if !config['devices'] return false end
        if !config['devices'].contains(deviceId) return false end
        
        var device = config['devices'][deviceId]
        if !device.contains('bindings') return false end
        
        var button_key = 'button' + str(button)
        if device['bindings'].contains(button_key)
            device['bindings'].remove(button_key)
            ewe_helpers.write_config(config)
            return true
        end
        return false
    end
end

class ewe_remote : Driver
    static XOR_TABLE = [
        15, 57, 190, 95, 39, 5, 190, 249, 102, 181, 116,
        13, 4, 134, 210, 97, 85, 187, 252, 22, 52, 64,
        126, 29, 56, 110, 228, 6, 170, 121, 50, 149, 102,
        181, 116, 13, 219, 140, 233, 1, 42
    ]
    static button_actions = ['simple', 'double', 'long']
    static types = {0x46: "S-MATE2", 0x47: "R5"}
    var last_data

    def init()
        import BLE
        import cb
        var cbp = cb.gen_cb(/svc,manu->self.ble_cb(svc,manu))
        BLE.adv_cb(cbp,cbuf)
        self.last_data = bytes('')
        tasmota.add_fast_loop(/-> BLE.loop())
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
        if ewe_helpers.get_topic_mode() == 1
            return "tele/tasmota_ble/" + device_id
        else
            var macFormatted = getmac(6)
            var fullTopic = string.replace(string.replace(
                tasmota.cmd('FullTopic', true)['FullTopic'],
                '%topic%', tasmota.cmd('Topic', true)['Topic']),
                '%prefix%', tasmota.cmd('Prefix', true)['Prefix3'])
            return string.replace(fullTopic, '%06X', macFormatted) + 'SWITCH'
        end
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

    def parse(d, RSSI, device_type, sequence)
        var result = self.test_button(d)
        if !result return end

        var timestamp = tasmota.rtc()['local']
        
        # Mise à jour des variables globales pour web_sensor
        g_state.button = result['button']
        g_state.action = result['action']
        g_state.deviceId = result['device_id']
        g_state.type = device_type
        g_state.signal = RSSI
        g_state.seq = sequence
        g_state.time = timestamp

        # Vérifier s'il y a un binding pour ce bouton et actionner le relais
        var relay = ewe_helpers.get_relay_binding(result['device_id'], result['button'])
        if relay != nil && result['action'] == 'simple'  # Ne réagit qu'aux clics simples
            # Toggle le relais
            var power = tasmota.get_power()
            if power != nil && relay <= size(power)
                tasmota.cmd(format('Power%d toggle', relay))
            end
        end

        # Création et envoi du message MQTT
        var msg = format(
            '{\"Button%d\":{\"Action\":\"%s\"},\"Signal\":%d,\"DeviceType\":\"%s\",\"Sequence\":%d,\"Timestamp\":%d}',
            result['button'], result['action'], RSSI, device_type, sequence, timestamp
        )
        mqtt.publish(self.get_mqtt_topic(result['device_id']), msg)

        # Génération de l'événement Tasmota
        tasmota.cmd(format("Event Button%d_%s", result['button'], result['action']))
    end

    def web_sensor()
        if g_state.button == -1 return nil end

        var deviceId = g_state.deviceId
        var isRegistered = ewe_helpers.is_device_registered(deviceId)
        
        var power_count = 0
        var power = tasmota.get_power()
        if power != nil
            power_count = size(power)
        end

        var num_buttons = g_state.type == 'S-MATE2' ? 3 : 6

        var buttons = ''
        if isRegistered
            # Première ligne : Titre et bouton Remove
            buttons = format(
                '<div style="display:flex; justify-content:space-between; align-items:center">' ..
                '<span>REMOTE SWITCH (%s)</span>' ..
                '<button style="background-color: #ff4444; color: white" onclick="fetch(\'cm?cmnd=EweRemoveDevice %s\')">Remove Device</button>' ..
                '</div>',
                g_state.type, deviceId
            )
            
            if power_count > 0
                # Ligne des boutons
                buttons = buttons + '<div style="display:flex">' ..
                                   '<span style="min-width:120px; line-height:30px">Select button:</span>' ..
                                   '<div style="display:flex; flex:1; justify-content:flex-start; margin-left:20px; margin-right:20px">'
                for btn: 1..num_buttons
                    var btnStyle = g_state.button == btn ? 
                        'background-color: #FFA500; color: white;' :  # Orange pour le bouton actif
                        'background-color: #808080; color: white;'    # Gris pour les autres
                    buttons = buttons + format(
                        '<button onclick="this.style.backgroundColor=\'#FFA500\';' ..
                        'document.querySelectorAll(\'.btn-number\').forEach(el=>{if(el!=this)el.style.backgroundColor=\'#808080\'});' ..
                        'var b=this.innerText;' ..
                        'document.querySelectorAll(\'.relay-btn\').forEach(el=>{' ..
                        'el.onclick=function(){' ..
                        'var actions=Array.from(document.querySelectorAll(\'.btn-action[style*=\\\'#FFA500\\\']).values()).map(b=>b.innerText);' ..
                        'if(actions.length==0)actions=[\'simple\'];' ..
                        'fetch(\'cm?cmnd=EweBindRelay %s_\'+b+\'_\'+this.innerText+\'_\'+actions.join(\',\'))}})" ' ..
                        'class="btn-number" style="margin:2px; min-width:30px; height:30px; %s">%d</button>',
                        deviceId, btnStyle, btn
                    )
                end
                buttons = buttons + '</div></div>'

                # Ligne des actions
                buttons = buttons + '<div style="display:flex">' ..
                                   '<span style="min-width:120px; line-height:30px">Select action:</span>' ..
                                   '<div style="display:flex; flex:1; justify-content:flex-start; margin-left:20px; margin-right:20px">'
                var actions = ['simple', 'double', 'hold']
                for action: actions
                    var actionStyle = g_state.action == action ? 
                        'background-color: #FFA500; color: white;' :  # Orange pour l'action active
                        'background-color: #808080; color: white;'    # Gris pour les autres
                    buttons = buttons + format(
                        '<button onclick="' ..
                        'this.style.backgroundColor = ' ..
                        'this.style.backgroundColor==\'rgb(255, 165, 0)\'?\'#808080\':\'#FFA500\';" ' ..
                        'class="btn-action" style="margin:2px; min-width:60px; height:30px; %s">%s</button>',
                        actionStyle, action
                    )
                end
                buttons = buttons + '</div></div>'

                # Ligne des relais
                buttons = buttons + '<div style="display:flex">' ..
                                   '<span style="min-width:120px; line-height:30px">Select relay to bind:</span>' ..
                                   '<div style="display:flex; flex:1; justify-content:flex-start; margin-left:20px; margin-right:20px">'
                for relay: 1..power_count
                    var currentBinding = ewe_helpers.get_relay_binding(deviceId, g_state.button)
                    var style = 'margin:2px; min-width:30px; height:30px; '
                    
                    if currentBinding == relay
                        style = style + 'background-color: #4CAF50; color: white;'  # Vert si lié
                    else
                        style = style + 'background-color: #2196F3; color: white;'  # Bleu si non lié
                    end
                    
                    buttons = buttons + format(
                        '<button class="relay-btn" style="%s">%d</button>',
                        style, relay
                    )
                end
                buttons = buttons + '</div></div>'
            end
        else
            # Bouton d'ajout (vert)
            buttons = format(
                '<button style="background-color: #4CAF50; color: white" onclick="fetch(\'cm?cmnd=EweAddDevice %s\')">Save Device</button>',
                deviceId
            )
        end

        var msg = format(
            '{s}%s{e}'..
            '{s}%s Button{m}%d{e}'..
            '{s}%s Action{m}%s{e}'..
            '{s}%s Signal{m}%d dBm{e}'..
            '{s}%s Sequence{m}%d{e}'..
            '{s}%s Timestamp{m}%d{e}'..
            '{s}<hr>{e}',
            buttons,
            deviceId, g_state.button,
            deviceId, g_state.action,
            deviceId, g_state.signal,
            deviceId, g_state.seq,
            deviceId, g_state.time
        )
        tasmota.web_send(msg)
    end
end

# Commandes Tasmota
def cmd_add_device(cmd, idx, payload, payload_json)
    # Nettoie le payload des éventuels caractères supplémentaires
    var deviceId = payload
    if string.find(payload, '_') > 0
        deviceId = string.split(payload, '_')[1]  # Prend la partie après le _
    end
    
    # Si deviceId est vide, affiche la liste des devices
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
    
    # Enlève tout ce qui n'est pas hexadécimal
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

def cmd_bind_relay(cmd, idx, payload, payload_json)
    if payload == ''
        # Liste tous les bindings existants
        var bindings = ewe_helpers.list_bindings()
        if size(bindings) == 0
            tasmota.resp_cmnd_str('No bindings configured')
            return
        end
        tasmota.resp_cmnd_str(json.dump(bindings))
        return
    end
    
    var parts = string.split(payload, '_')
    if size(parts) != 3
        tasmota.resp_cmnd_str('Invalid format. Use: deviceId_button_relay')
        return
    end
    
    var deviceId = parts[0]
    var button = int(parts[1])
    var relay = int(parts[2])
    
    # Si le relais est déjà lié à ce bouton, on supprime le binding
    var current_binding = ewe_helpers.get_relay_binding(deviceId, button)
    if current_binding == relay
        if ewe_helpers.remove_binding(deviceId, button)
            tasmota.resp_cmnd_str(format('Binding removed for button %d', button))
        else
            tasmota.resp_cmnd_failed()
        end
        return
    end
    
    # Sinon, on crée ou met à jour le binding
    if ewe_helpers.set_relay_binding(deviceId, button, relay)
        tasmota.resp_cmnd_str(format('Button %d bound to relay %d', button, relay))
    else
        tasmota.resp_cmnd_failed()
    end
end

def cmd_set_topic_mode(cmd, idx, payload, payload_json)
    if payload == ''
        # Si pas d'argument, renvoie la valeur actuelle
        var current_mode = ewe_helpers.get_topic_mode()
        tasmota.resp_cmnd_str(str(current_mode))
        return
    end
    
    var mode = int(payload)
    if mode == 0 || mode == 1
        ewe_helpers.set_topic_mode(mode)
        tasmota.resp_cmnd_str(str(mode))  # Utilise resp_cmnd_str pour le format correct
    else
        tasmota.resp_cmnd_failed()
    end
end

# Initialisation
ewe = ewe_remote()
tasmota.add_driver(ewe)
tasmota.add_cmd('EweAddDevice', cmd_add_device)
tasmota.add_cmd('EweTopic', cmd_set_topic_mode)
tasmota.add_cmd('EweRemoveDevice', cmd_remove_device)
tasmota.add_cmd('EweBindRelay', cmd_bind_relay)
