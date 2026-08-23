do
  import introspect
  var ewe_remote_extension = introspect.module('ewe_remote', true)
  tasmota.add_extension(ewe_remote_extension)
end
