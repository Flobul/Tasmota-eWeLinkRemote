import string
import path

var base_url = "https://raw.githubusercontent.com/Flobul/Tasmota-eWeLinkRemote/main/"
var ewe_temp = "ewe_temp.be"

var files = {
    'remote': "ewe_remote.be",
    'dimmer': "ewe_remote_dimmer.be"
}

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
    import json

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

            result[name] = {
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

tasmota.add_cmd('EweCheckUpdate', cmd_check_update)
tasmota.add_cmd('EweUpdate', cmd_do_update)