import string
import path
import json

var base_url = "https://raw.githubusercontent.com/Flobul/Tasmota-eWeLinkRemote/main/"
var ewe_temp = "ewe_temp.be"
var files = {
    'remote': "ewe_remote.be",
    'dimmer': "ewe_remote_dimmer.be"
}
var cron_rule = nil

def get_version_from_file(filename)
    try
        var f = open(filename, "r")
        for i:0..9
            var line = f.readline()
            if !line break end
            if string.find(line, "# Version") >= 0
                var version = line[string.find(line, "# Version") + 10..string.find(line, "# Version") + 14]
                f.close()
                return version
            end
        end
        f.close()
    except ..
        #print(format("ERR: Cannot read %s", filename))
    end
    return nil
end

def cmd_check_update(cmd, idx, payload, payload_json)
    var result = {}
    var found = false

    for name: files.keys()
        var current = get_version_from_file(files[name])
        if !current continue end
        found = true

        try
            var cl = webclient()
            cl.begin(base_url + files[name])
            if cl.GET() != 200 continue end

            cl.write_file(ewe_temp)
            var remote = get_version_from_file(ewe_temp)
            path.remove(ewe_temp)

            if !remote continue end

            result[files[name]] = {
                'current': current,
                'new': remote,
                'update': remote != current
            }
        except ..
            path.remove(ewe_temp)
        end
    end

    if !found
        tasmota.resp_cmnd('{"Error":"No files found"}')
        return
    end

    tasmota.resp_cmnd(json.dump(result))
end

def cmd_do_update(cmd, idx, payload, payload_json)
    try
        var updated = false
        for name: files.keys()
            var current = get_version_from_file(files[name])
            if !current continue end

            var cl = webclient()
            cl.begin(base_url + files[name])
            if cl.GET() == 200
                cl.write_file(files[name])
                updated = true
            end
        end
        
        if updated
            tasmota.resp_cmnd('{"Status":"Success","Message":"Update successful. Restarting in 2 seconds"}')
            tasmota.set_timer(2000, /-> tasmota.cmd('Restart 1'))
        else
            tasmota.resp_cmnd('{"Status":"Success","Message":"No updates needed"}')
        end
    except ..
        tasmota.resp_cmnd('{"Error":"Update failed"}')
    end
end

def save_config(key, value)
    try
        var config = {}
        try
            var f = open('ewe_config.json', 'r')
            config = json.load(f.read())
            f.close()
        except .. 
            print('DBG: Creating new config file')
        end

        config[key] = value

        var f = open('ewe_config.json', 'w')
        f.write(json.dump(config))
        f.close()
        return true
    except .. as e
        print(format('ERR: Cannot save config: %s', e))
        return false
    end
end

def load_config(key)
    try
        var f = open('ewe_config.json', 'r')
        var config = json.load(f.read())
        f.close()
        return config.find(key, false)
    except ..
        return false
    end
end

def cmd_auto_update(cmd, idx, payload, payload_json)
    
    if !payload
        var auto = load_config('auto_update')
        tasmota.resp_cmnd(format('{"AutoUpdate":"%s"}', auto ? "1" : "0"))
        return
    end

    var enabled = payload == "1" || payload == "true" || payload == "on"
    
    if cron_rule != nil
        tasmota.remove_rule(cron_rule)
        cron_rule = nil
    end

    save_config('auto_update', enabled)

    if enabled
        cron_rule = tasmota.add_rule("Time#Minute=0", def ()
            if tasmota.time_str(tasmota.rtc()['local'])['hour'] == "00"
                cmd_check_update(nil, nil, nil, nil)
            end
        end)
        tasmota.resp_cmnd('{"AutoUpdate":"1","Message":"Auto update enabled, will check at midnight"}')
    else
        tasmota.resp_cmnd('{"AutoUpdate":"0","Message":"Auto update disabled"}')
    end
end

var auto = load_config('auto_update')
if auto
    cmd_auto_update(nil, nil, "1", nil)
end

tasmota.add_cmd('EweCheckUpdate', cmd_check_update)
tasmota.add_cmd('EweUpdate', cmd_do_update)
tasmota.add_cmd('EweAutoUpdate', cmd_auto_update)