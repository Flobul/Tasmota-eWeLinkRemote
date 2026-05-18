# rm eWeLinkRemote_Dimmer.tapp; zip -j -0 eWeLinkRemote_Dimmer.tapp tapp/dimmer/autoexec.be tapp/dimmer/manifest.json ewe_remote_dimmer.be ewe_update.be
tasmota.add_rule('System#Boot', def ()
  tasmota.set_timer(10000, / -> load('ewe_remote_dimmer.be'))
end)
