# rm eWeLinkRemote.tapp; zip -j -0 eWeLinkRemote.tapp tapp/remote/autoexec.be tapp/remote/manifest.json ewe_remote.be ewe_update.be
tasmota.add_rule('System#Boot', def ()
  tasmota.set_timer(10000, / -> load('ewe_remote.be'))
end)
