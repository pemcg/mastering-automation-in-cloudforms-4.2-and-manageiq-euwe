$evm.log(:info, "get_credentials started")

servername = $evm.object['servername']
username   = $evm.object['username']
password   = $evm.object.decrypt('password')

$evm.log(:info, "Server: #{servername}, Username: #{username}, Password: #{password}")
exit MIQ_OK