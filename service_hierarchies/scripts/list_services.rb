begin

  def get_visible_tenant_ids
    tenant_ancestry = []
    tenant_ancestry << $evm.root['tenant'].id
    $evm.vmdb(:tenant).all.each do |tenant|
      unless tenant.ancestry.nil?
        ancestors = tenant.ancestry.split('/')
        if ancestors.include?($evm.root['tenant'].id.to_s)
          tenant_ancestry << tenant.id
        end
      end
    end
    tenant_ancestry
  end

  def get_current_group_rbac_array(rbac_array=[])
    user = $evm.root['user']
    unless user.current_group.filters.blank?
      user.current_group.filters['managed'].flatten.each do |filter|
        next unless /(?<category>\w*)\/(?<tag>\w*)$/i =~ filter
        rbac_array << {category => tag}
      end
    end
    $evm.log(:info, "rbac filters: #{rbac_array}")
    rbac_array
  end
   
  def service_visible?(visible_tenants, rbac_array, service)
    visible = false
    $evm.log(:info, "Evaluating Service #{service.name}")
    if visible_tenants.include?(service.tenant.id)
      if rbac_array.length.zero?
        $evm.log(:info, "No filter, service: #{service.name} is visible to this user")
        visible = true
      else
        rbac_array.each do |rbac_hash|
          rbac_hash.each do |category, tag|
            if service.tagged_with?(category, tag)
              $evm.log(:info, "Service: #{service.name} is visible to this user")
              visible = true
            end
          end
        end
      end
    end
    visible
  end

  rbac_array = get_current_group_rbac_array
  visible_tenants = get_visible_tenant_ids
  values_hash      = {}
  visible_services = []
  
  $evm.vmdb(:service).all.each do |service|
    if service['display']
      $evm.log(:info, "Found service: #{service.name}")
      if service_visible?(visible_tenants, rbac_array, service)
        $evm.log(:info, "Service visible to this tenant")
        visible_services << service
      end
    end
  end
  if visible_services.length > 0
    if visible_services.length > 1
      values_hash['!'] = '-- select from list --'
    end
    visible_services.each do |service|
      values_hash[service.id] = service.name
    end
  else
    values_hash['!'] = 'No services are available'
  end

  list_values = {
      'sort_by'    => :description,
      'data_type'  => :string,
      'required'   => true,
      'values'     => values_hash
  }
  list_values.each { |key, value| $evm.object[key] = value }
  exit MIQ_OK
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end

