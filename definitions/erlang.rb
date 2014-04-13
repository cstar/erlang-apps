#
# Author:: Joe Williams (<j@boundary.com>)
# Cookbook Name:: apps
# Definition:: erlang
#
# Copyright 2011, Boundary
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
#

#
# install standard erlang dependencies
#

define :install_standard_erlang_dependencies, :name => nil, :deploy_config => nil do
  include_recipe "erlang_apps::erl_call"
  # include_recipe "erlang_apps::epmd"

end

#
# install erlang release
#

define :install_erlang_release, :name => nil, :deploy_config => nil do
  
  common_configs = data_bag_item("forest", "common")
  
  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  filename = "#{deploy_config["id"]}_#{deploy_config["version"]}.tar.gz"
  github_authorization_token = data_bag_item("forest", "deploy_key")["authorization_token"]
  
  directory deploy_config["install"]["path"]
  
  remote_file "/tmp/#{filename}" do
    source "#{deploy_config["install"]["repo_url"]}/tarball/#{deploy_config["id"]}_#{deploy_config["version"]}"
    headers({ 
      "Authorization" => "token #{github_authorization_token}" 
    })
    mode 0644
    not_if "/usr/bin/test -d #{deploy_config["install"]["path"]}/releases/#{deploy_config["version"]}"
  end
  
  bash "install #{deploy_config["id"]}" do
    user "root"
    cwd "/opt"
    code <<-EOH
    (tar zxf /tmp/#{filename} -C #{deploy_config["install"]["path"]} --strip-components 1)
    (rm -f /tmp/#{filename})
    EOH
    not_if "/usr/bin/test -d #{deploy_config["install"]["path"]}/releases/#{deploy_config["version"]}"
  end
  
  # bash "use system ERTS" do
  #   user "root"
  #   cwd deploy_config["install"]["path"]
  #   code <<-EOH
  #   ERTS_DIR=`echo erts-*`
  #   rm -fR $ERTS_DIR
  #   ln -s #{node["forest"]["system-erts"]} $ERTS_DIR
  #   EOH
  #   not_if do 
  #     File.exists?(`echo erts-*`) and File.symlink? `echo erts-*`
  #   end
  # end

end

#
# erlang main config
#

define :erlang_config, :name => nil, :deploy_config => nil, :app_options => nil do

  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  # if ::File.exists?("#{deploy_config["install"]["path"]}/releases/#{deploy_config["version"]}")
    template "#{deploy_config["install"]["path"]}/releases/#{deploy_config["version"]}/sys.config" do
      source "#{ deploy_config["id"].split("_").join("/") }.config.erb"
      owner deploy_config["system"]["user"]
      group deploy_config["system"]["group"]
      mode 0644
      variables :deploy_config => deploy_config, :app_options => params[:app_options]
      notifies :restart, resources(:service => "#{deploy_config["id"]}")
    end
  # end

end

#
# erlang vm.args
#

define :erlang_vm_args, :name => nil, :deploy_config => nil, :app_options => nil do

  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  # if ::File.exists?("#{deploy_config["install"]["path"]}/releases/#{deploy_config["version"]}")
    template "#{deploy_config["install"]["path"]}/releases/#{deploy_config["version"]}/vm.args" do
      source "vm.args.erb"
      owner deploy_config["system"]["user"]
      group deploy_config["system"]["group"]
      mode 0644
      variables :deploy_config => deploy_config, :app_options => params[:app_options]
      notifies :restart, resources(:service => "#{deploy_config["id"]}")
    end
  # end

end

#
# erlang hot upgrade
#

define :erlang_hot_upgrade, :name => nil, :deploy_config => nil, :upgrade_code => nil, :app_options => nil do
  common_configs = data_bag_item("forest", "common")

  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  remote_file "#{deploy_config["install"]["path"]}/releases/#{filename}" do
    source "#{deploy_config["install"]["repo_url"]}/#{deploy_config["id"]}/upgrades/#{filename}"
    owner deploy_config["system"]["user"]
    group deploy_config["system"]["group"]
    not_if "/usr/bin/test -d #{deploy_config["install"]["path"]}/releases/#{deploy_config["version"]}"
  end

  unpack_code = <<-EOH
  {ok, _} = release_handler:unpack_release("#{deploy_config["id"]}_#{deploy_config["version"]}").
  EOH

  erl_call "unpack #{deploy_config["id"]}" do
    node_name "#{deploy_config["id"]}@#{node[:fqdn]}"
    name_type "name"
    cookie common_configs["cookie"]
    code unpack_code
    not_if "/usr/bin/test -d #{deploy_config["install"]["path"]}/releases/#{deploy_config["version"]}"
  end

  template "#{deploy_config["install"]["path"]}/releases/#{deploy_config["version"]}/sys.config" do
    source "config.erb"
    owner deploy_config["system"]["user"]
    group deploy_config["system"]["group"]
    mode 0644
    variables :deploy_config => deploy_config, :app_options => params[:app_options]
  end

  template "#{deploy_config["install"]["path"]}/releases/#{deploy_config["version"]}/vm.args" do
    source "vm.args.erb"
    owner deploy_config["system"]["user"]
    group deploy_config["system"]["group"]
    mode 0644
    variables :deploy_config => deploy_config, :app_options => params[:app_options]
  end

  if params[:upgrade_code]
    upgrade_code = params[:upgrade_code]
  else
    upgrade_code = <<-EOH
    {ok, _, _} = release_handler:install_release("#{deploy_config["version"]}"),
    ok = release_handler:make_permanent("#{deploy_config["version"]}").
    EOH
  end

  erl_call "upgrade #{deploy_config["id"]}" do
    node_name "#{deploy_config["id"]}@#{node[:fqdn]}"
    name_type "name"
    cookie common_configs["cookie"]
    code upgrade_code
    not_if do
        (`cat #{deploy_config["install"]["path"]}/releases/start_erl.data`.include?(deploy_config["version"]))
    end
  end

end