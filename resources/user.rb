#
# Cookbook Name:: openvpn
# Resource:: users
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

property :cookbook, String, default: 'openvpn'
property :data_bag, String, default: 'users'
property :user_query, String, default: lazy { node['openvpn']['user_query'] }
property :remove_user_query, String, default: lazy { node['openvpn']['remove_user_query'] }
property :key_dir, String, default: lazy { node['openvpn']['key_dir'] }
property :client_prefix, String, default: lazy { node['openvpn']['client_prefix'] }
property :ca_expire, String, default: lazy { node['openvpn']['key']['ca_expire'].to_s }
property :expire, String, default: lazy { node['openvpn']['key']['expire'].to_s }
property :size, String, default: lazy { node['openvpn']['key']['size'].to_s }
property :country, String, default: lazy { node['openvpn']['key']['country'] }
property :province, String, default: lazy { node['openvpn']['key']['province'] }
property :city, String, default: lazy { node['openvpn']['key']['city'] }
property :org, String, default: lazy { node['openvpn']['key']['org'] }
property :email, String, default: lazy { node['openvpn']['key']['email'] }
property :cookbook_user_conf, String, default: lazy { node['openvpn']['cookbook_user_conf'] }

action :create do
  search(new_resource.data_bag, new_resource.user_query) do |user_result|
    execute "generate-openvpn-#{user_result['id']}" do
      command "./pkitool #{user_result['id']}"
      cwd '/etc/openvpn/easy-rsa'
      environment(
        'EASY_RSA'     => '/etc/openvpn/easy-rsa',
        'KEY_CONFIG'   => '/etc/openvpn/easy-rsa/openssl.cnf',
        'KEY_DIR'      => new_resource.key_dir,
        'CA_EXPIRE'    => new_resource.ca_expire,
        'KEY_EXPIRE'   => new_resource.expire,
        'KEY_SIZE'     => new_resource.size,
        'KEY_COUNTRY'  => new_resource.country,
        'KEY_PROVINCE' => new_resource.province,
        'KEY_CITY'     => new_resource.city,
        'KEY_ORG'      => new_resource.org,
        'KEY_EMAIL'    => new_resource.email
      )
      not_if { ::File.exist?("#{new_resource.key_dir}/#{user_result['id']}.crt") }
    end

    %w(conf ovpn).each do |ext|
      template "#{new_resource.key_dir}/#{new_resource.client_prefix}-#{user_result['id']}.#{ext}" do
        source 'client.conf.erb'
        cookbook new_resource.cookbook_user_conf
        variables(client_cn: user_result['id'])
      end
    end

    execute "create-openvpn-tar-#{user_result['id']}" do
      cwd new_resource.key_dir
      command <<-EOH
        tar zcf #{user_result['id']}.tar.gz ca.crt #{user_result['id']}.crt #{user_result['id']}.key #{new_resource.client_prefix}-#{user_result['id']}.conf #{new_resource.client_prefix}-#{user_result['id']}.ovpn
      EOH
      not_if { ::File.exist?("#{new_resource.key_dir}/#{user_result['id']}.tar.gz") }
    end
  end
end

action :remove do
  search(new_resource.data_bag, new_resource.remove_user_query) do |user_result|
    execute "revoke-openvpn-#{user_result['id']}" do
      command '. /etc/openvpn/easy-rsa/vars && openssl ca -revoke ' \
              "#{new_resource.key_dir}/#{user_result['id']}.crt " \
              "-config #{new_resource.key_dir}/openssl.cnf"
      cwd new_resource.key_dir
      environment(
        'KEY_CN'        => '',
        'KEY_OU'        => '',
        'KEY_NAME'      => '',
        'KEY_ALTNAMES'  => ''
      )
      only_if do
        ::File.exist?("#{new_resource.key_dir}/#{user_result['id']}.crt") &&
          cert_valid?(new_resource.key_dir, "#{user_result['id']}.crt")
      end
      notifies :run, 'execute[gencrl]', :immediately
    end

    ruby_block "check-#{user_result['id']}-revocation" do
      block do
        if cert_valid?(new_resource.key_dir, "#{user_result['id']}.crt")
          Chef::Log.fatal("Failed to revoke certificate for #{user_result['id']}")
          raise "#{new_resource.key_dir}/#{user_result['id']}.crt is still valid"
        end
      end
      only_if { ::File.exist?("#{new_resource.key_dir}/#{user_result['id']}.crt") }
    end

    %w(tar.gz crt key csr).each do |ext|
      file "#{new_resource.key_dir}/#{user_result['id']}.#{ext}" do
        action :delete
      end
    end
    %w(conf ovpn).each do |ext|
      file "#{new_resource.key_dir}/" \
           "#{new_resource.client_prefix}-#{user_result['id']}.#{ext}" do
        action :delete
      end
    end
  end
end

action_class do
  include OpenVPN::Helper
=======
# Cookbook:: openvpn
# Resource:: user
#

property :client_name, String, name_property: true
property :create_bundle, [true, false], default: true
property :force, [true, false]
property :destination, String
property :additional_vars, Hash, default: {}

# TODO: this action will not recreate if the client configuration data has
#       changed. Requires manual intervention.

action :create do
  # Setup some variables
  key_dir = node['openvpn']['key_dir']
  cert_path = ::File.join(key_dir, "#{new_resource.client_name}.crt")
  ca_cert_path = ::File.join(key_dir, 'ca.crt')
  key_path = ::File.join(key_dir, "#{new_resource.client_name}.key")
  client_file_basename = [node['openvpn']['client_prefix'], new_resource.client_name].join('-')
  destination_path = ::File.expand_path(new_resource.destination || key_dir)
  bundle_filename = "#{new_resource.client_name}.tar.gz"
  bundle_full_path = ::File.expand_path(::File.join(destination_path, bundle_filename))

  execute "generate-openvpn-#{new_resource.client_name}" do
    command "./pkitool #{new_resource.client_name}"
    cwd '/etc/openvpn/easy-rsa'
    environment(
      'EASY_RSA'     => '/etc/openvpn/easy-rsa',
      'KEY_CONFIG'   => '/etc/openvpn/easy-rsa/openssl.cnf',
      'KEY_DIR'      => key_dir,
      'CA_EXPIRE'    => node['openvpn']['key']['ca_expire'].to_s,
      'KEY_EXPIRE'   => node['openvpn']['key']['expire'].to_s,
      'KEY_SIZE'     => node['openvpn']['key']['size'].to_s,
      'KEY_COUNTRY'  => node['openvpn']['key']['country'],
      'KEY_PROVINCE' => node['openvpn']['key']['province'],
      'KEY_CITY'     => node['openvpn']['key']['city'],
      'KEY_ORG'      => node['openvpn']['key']['org'],
      'KEY_EMAIL'    => node['openvpn']['key']['email']
    )
    creates cert_path unless new_resource.force
  end

  cleanup_name = "cleanup-old-bundle-#{new_resource.client_name}"

  template "#{destination_path}/#{client_file_basename}.conf" do
    source 'client.conf.erb'
    cookbook node['openvpn']['cookbook_user_conf']
    variables(client_cn: new_resource.client_name)
    notifies :delete, "file[#{cleanup_name}]", :immediately
    only_if { new_resource.create_bundle }
  end

  template "#{destination_path}/#{client_file_basename}.ovpn" do
    source new_resource.create_bundle ? 'client.conf.erb' : 'client-inline.conf.erb'
    cookbook node['openvpn']['cookbook_user_conf']
    if new_resource.create_bundle
      variables(client_cn: new_resource.client_name)
    else
      sensitive true
      variables(
        lazy do
          {
            client_cn: new_resource.client_name,
            ca: IO.read(ca_cert_path),
            cert: IO.read(cert_path),
            key: IO.read(key_path),
          }.merge(new_resource.additional_vars) { |key, oldval, newval| oldval } # rubocop:disable Lint/UnusedBlockArgument
        end
      )
    end
    notifies :delete, "file[#{cleanup_name}]", :immediately
  end

  file cleanup_name do
    action :nothing

    path bundle_full_path
  end

  execute "create-openvpn-tar-#{new_resource.client_name}" do
    cwd destination_path
    filelist = "ca.crt #{new_resource.client_name}.crt #{new_resource.client_name}.key #{client_file_basename}.ovpn"
    filelist += " #{client_file_basename}.conf" if new_resource.create_bundle
    command "tar zcf #{bundle_filename} #{filelist}"
    creates bundle_full_path unless new_resource.force
  end
end

action :delete do
  key_dir = node['openvpn']['key_dir']
  client_file_basename = [node['openvpn']['client_prefix'], new_resource.client_name].join('-')
  destination_path = ::File.expand_path(new_resource.destination || key_dir)
  bundle_filename = "#{new_resource.client_name}.tar.gz"
  bundle_full_path = ::File.expand_path(::File.join(destination_path, bundle_filename))

  %w(conf ovpn).each do |ext|
    file "#{destination_path}/#{client_file_basename}.#{ext}" do
      action :delete
    end
    file bundle_full_path do
      action :delete
      only_if { new_resource.create_bundle }
    end
  end
end