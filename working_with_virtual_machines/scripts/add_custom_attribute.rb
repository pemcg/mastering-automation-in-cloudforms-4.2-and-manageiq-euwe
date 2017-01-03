$evm.log(:info, "add_custom_attribute started")
#
# Get the VM object
#
vm = $evm.root['vm']
#
# Get the dialog values
#
key   = $evm.root['dialog_key']
value = $evm.root['dialog_value']
#
# Set the custom attribute
#
vm.custom_set(key, value)
exit MIQ_OK