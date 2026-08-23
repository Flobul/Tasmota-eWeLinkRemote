# Manual .be installation only. A .tapp starts its embedded script itself.
import path
load('ewe_remote.be')
# load('ewe_remote_dimmer.be')
if path.exists('ewe_update.be')
  load('ewe_update.be')
end
