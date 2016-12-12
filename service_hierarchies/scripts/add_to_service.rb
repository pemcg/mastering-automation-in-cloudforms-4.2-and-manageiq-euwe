begin
  new_service_id = $evm.root['dialog_service']
  new_service = $evm.vmdb('service', new_service_id) rescue nil
  if new_service.nil?
    $evm.log(:error, "Can't find service with ID: #{new_service_id}")
    exit MIQ_ERROR
  else
    case $evm.root['vmdb_object_type']
    when 'service'
      $evm.log(:info, "Adding Service #{$evm.root['service'].name} to #{new_service.name}")
      $evm.root['service'].parent_service = new_service
    when 'vm'
      vm = $evm.root['vm']
      #
      # See if the VM is already part of a service
      #
      unless vm.service.nil?
        old_service = vm.service
        vm.remove_from_service
        if old_service.v_total_vms.zero?
          $evm.log(:info, "Old service #{old_service.name} is now empty, removing it from VMDB")
          old_service.remove_from_vmdb
        end
      end
      $evm.log(:info, "Adding VM #{vm.name} to #{new_service.name}")
      vm.add_to_service(new_service)
      #
      # Set the VM's ownership to be the same as the new group
      #
      vm.owner = $evm.vmdb(:user).find_by_id(new_service.evm_owner_id) unless new_service.evm_owner_id.nil?
      vm.group = $evm.vmdb(:miq_group).find_by_id(new_service.miq_group_id) unless new_service.miq_group_id.nil?
    end
  end
  exit MIQ_OK
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ERROR
end

