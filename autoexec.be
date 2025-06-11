def system_boot()
  tasmota.set_timer(10000, / -> load('ewe_remote.be'))
  #tasmota.set_timer(10000, / -> load('ewe_remote_dimmer.be'))
end
tasmota.add_rule('System#Boot', system_boot)
