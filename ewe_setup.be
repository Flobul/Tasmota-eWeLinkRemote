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
    load('ewe_remote.be')
    #load('ewe_remote_dimmer.be')
    return true
  end
  return false
end

start_eweremote_setup()