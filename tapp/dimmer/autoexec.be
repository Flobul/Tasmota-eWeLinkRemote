do
  import introspect
  var ewe_remote_dimmer_extension = introspect.module('ewe_remote_dimmer', true)
  tasmota.add_extension(ewe_remote_dimmer_extension)
end
