# This code is for the eWeLink BLE remote control
# Created by @Flobul on 2025-03-10
# Version 0.1.0

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
var col_text = tasmota.webcolor(1)                  # Couleur du texte
var col_background = tasmota.webcolor(2)            # Couleur de fond des cards
var col_button_default = tasmota.webcolor(3)        # Couleur des boutons normaux
var col_button = tasmota.webcolor(10)               # Couleur des boutons menu
var col_button_hover = tasmota.webcolor(11)         # Couleur des boutons menu
var col_button_delete = tasmota.webcolor(12)        # Couleur du bouton de suppression
var col_button_delete_hover = tasmota.webcolor(13)  # Couleur du bouton de suppression
var col_button_success = tasmota.webcolor(14)       # Couleur du bouton de validation
var col_button_success_hover = tasmota.webcolor(15) # Couleur du bouton de validation

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
        var devType = g_state.type
        if !devType devType = 'R5' end
        config['devices'][deviceId] = {
            'added_at': tasmota.rtc()['local'],
            'bindings': {},
            'type': devType
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

    static def get_button_bindings(deviceId, button)
        var config = ewe_helpers.read_config()
        if !config['devices'] || !config['devices'].contains(deviceId) return [] end
        
        var device = config['devices'][deviceId]
        if !device.contains('bindings') return [] end
        
        var button_key = 'button' + str(button)
        if !device['bindings'].contains(button_key) return [] end
        
        return device['bindings'][button_key]
    end

    static def add_binding(deviceId, button, relay, actions)
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
        
        device['bindings'][button_key].push({
            'relay': relay,
            'actions': actions
        })
        
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
    var button_history  # Ajout de la variable button_history

    def init()
        import BLE
        import cb
        var cbp = cb.gen_cb(/svc,manu->self.ble_cb(svc,manu))
        BLE.adv_cb(cbp,cbuf)
        self.last_data = bytes('')
        self.button_history = {}  # Initialisation de button_history
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
        var bindings = ewe_helpers.get_button_bindings(result['device_id'], result['button'])
        if size(bindings) > 0
            var power = tasmota.get_power()
            if power != nil
                # Pour chaque binding
                for binding: bindings
                    # Vérifie si l'action correspond
                    if binding['actions'].find(result['action']) != nil
                        # Toggle le relais correspondant
                        if binding['relay'] <= size(power)
                            tasmota.cmd(format('Power%d toggle', binding['relay']))
                        end
                    end
                end
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
        var current_time = tasmota.rtc()['local']

        # Organiser l'historique par device
        if !self.button_history
            self.button_history = {}
        end

        # Créer une entrée pour ce device si elle n'existe pas
        if !self.button_history.contains(deviceId)
            self.button_history[deviceId] = {}
        end

        # Stocker l'état actuel dans l'historique pour ce device
        var button_key = str(g_state.button)
        self.button_history[deviceId][button_key] = {
            'button': g_state.button,
            'action': g_state.action,
            'signal': g_state.signal,
            'time': g_state.time,
            'type': g_state.type
        }

        # Nettoyer l'historique des entrées plus vieilles que 3600 secondes
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
                    '{s}<button style="background-color: %s; color: white; border:0; border-radius:0.3rem; padding:5px 10px; cursor:pointer; transition-duration:0.4s" ' ..
                    'onmouseover="this.style.backgroundColor=\'%s\'" ' ..  # Couleur hover pour Remove
                    'onmouseout="this.style.backgroundColor=\'%s\'" ' ..
                    'onclick="fetch(\'cm?cmnd=EweRemoveDevice %s\')">Remove Device</button>{e}',
                    col_button_delete, col_button_delete_hover, col_button_delete, dev
                )
            else
                msg += format(
                    '{s}<button style="background-color: %s; color: white; border:0; border-radius:0.3rem; padding:5px 10px; cursor:pointer; transition-duration:0.4s" ' ..
                    'onmouseover="this.style.backgroundColor=\'%s\'" ' ..  # Couleur hover pour Save
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

            # Configuration des boutons
            for btn: 1..num_buttons
                webserver.content_send(format(
                    '<div style="background:rgba(0,0,0,0.05)">' ..
                    '<div>Button %d</div>',
                    btn
                ))
                
                # Bindings actuels
                var current_bindings = device.find('bindings', {})
                var button_key = 'button' + str(btn)
                
                if current_bindings.contains(button_key)
                    var bindings = current_bindings[button_key]
                    for binding: bindings
                        webserver.content_send(format(
                            '<div style="background:%s; color:white; border-radius:3px; display:inline-flex; justify-content:space-between; align-items:center; transition-duration:0.4s" ' ..
                            'onmouseover="this.style.backgroundColor=\'%s\'" ' ..
                            'onmouseout="this.style.backgroundColor=\'%s\'">' ..
                            '<span>Relay %d [%s]</span>' ..
                            '<button onclick="fetch(\'cm?cmnd=EweRemoveBinding %s_%d_%d\').then(()=>window.location.reload())" ' ..
                            'style="background:none; border:none; color:white; cursor:pointer;width: 20px">' ..
                            '×</button>' ..
                            '</div>',
                            col_button_success,
                            col_button_delete,
                            col_button_success,
                            binding['relay'],
                            binding['actions'].concat(','),
                            deviceId, btn, binding['relay']
                        ))
                    end
                end
                
                # Interface d'ajout
                if power_count > 0
                    webserver.content_send(
                        '<div>' ..
                        '<select id="relay' + str(btn) + '_' + deviceId + '" style="width:auto; margin-right:5px">'
                    )
                    
                    for relay: 1..power_count
                        webserver.content_send(format(
                            '<option value="%d">Relay %d</option>',
                            relay, relay
                        ))
                    end
                    
                    webserver.content_send('</select>')
                    
                    webserver.content_send(
                        '<label style="margin:0 5px"><input type="checkbox" id="single' + str(btn) + '_' + deviceId + '" checked> Single</label>' ..  # 'Single' coché par défaut
                        '<label style="margin:0 5px"><input type="checkbox" id="double' + str(btn) + '_' + deviceId + '"> Double</label>' ..
                        '<label style="margin:0 5px"><input type="checkbox" id="hold' + str(btn) + '_' + deviceId + '"> Hold</label>' ..
                        format('<button onclick="addBinding(\'%s\',%d)" ' ..
                            'style="background:%s; color:white; border:none; padding:2px 8px; margin-left:5px; border-radius:3px; cursor:pointer; transition-duration:0.4s" ' ..
                            'onmouseover="this.style.backgroundColor=\'%s\'" ' ..
                            'onmouseout="this.style.backgroundColor=\'%s\'">Add</button>',
                            deviceId, btn, col_button, col_button_hover, col_button
                        ) ..
                        '</div>'
                    )
                end
                
                webserver.content_send('</div>')
            end
            
            # Bouton de suppression
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
        
        # JavaScript inchangé
        webserver.content_send(
            '<script>' ..
            'function addBinding(deviceId, btn) {' ..
            '  const relay = document.getElementById("relay"+btn+"_"+deviceId).value;' ..
            '  const actions = [];' ..
            '  if(document.getElementById("single"+btn+"_"+deviceId).checked) actions.push("single");' ..
            '  if(document.getElementById("double"+btn+"_"+deviceId).checked) actions.push("double");' ..
            '  if(document.getElementById("hold"+btn+"_"+deviceId).checked) actions.push("hold");' ..
            '  if(actions.length === 0) {' ..
            '    alert("Please select at least one action");' ..
            '    return;' ..
            '  }' ..
            '  fetch("cm?cmnd=EweAddBinding "+deviceId+"_"+btn+"_"+relay+"_"+actions.join(","))' ..
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

def cmd_add_binding(cmd, idx, payload, payload_json)
    var parts = string.split(payload, '_')
    if size(parts) != 4
        tasmota.resp_cmnd_str('Invalid format. Use: deviceId_button_relay_actions')
        return
    end
    
    var deviceId = parts[0]
    var button = int(parts[1])
    var relay = int(parts[2])
    var actions = string.split(parts[3], ',')
    
    if ewe_helpers.add_binding(deviceId, button, relay, actions)
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
tasmota.add_cmd('EweAddBinding', cmd_add_binding)
tasmota.add_cmd('EweRemoveBinding', cmd_remove_binding)

# Ajout du gestionnaire de page web pour la configuration
ewe.web_add_handler()
