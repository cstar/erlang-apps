#
# Author:: Joe Williams (<j@boundary.com>)
# Cookbook Name:: apps
# Definition:: apps
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
# install app dependencies
#

define :install_app_dependencies, :name => nil, :deploy_config => nil do

  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  if deploy_config["dependencies"]

    case deploy_config["type"]
    when "ruby"
      if deploy_config["dependencies"]["gems"]
        deploy_config["dependencies"]["gems"].each do |dep, version|
          if version == "latest"
            gem_package dep
          else
            gem_package dep do
              action :install
              version version
            end
          end
        end
      end
    end
    
    if deploy_config["dependencies"]["recipes"]
      deploy_config["dependencies"]["recipes"].each do |dep|
        include_recipe dep
      end
    end

    if deploy_config["dependencies"]["system"]
      deploy_config["dependencies"]["system"].each do |dep|
        package dep
      end
    end

  end

end

#
# setup runit service
#

define :setup_runit_service, :name => nil, :deploy_config => nil do

  include_recipe "runit"

  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  runit_service "#{deploy_config["id"]}" do
    run_template_name "app"
    log_template_name "app"
    options deploy_config.raw_data
  end

  service "#{deploy_config["id"]}" do
    supports :status => true, :restart => true
    action [ :start ]
  end

end

#
# user and group
#

define :create_user_group_home, :name => nil, :deploy_config => nil do

  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  group deploy_config["system"]["group"] do
    gid deploy_config["system"]["gid"]
  end

  user deploy_config["system"]["user"] do
    uid deploy_config["system"]["uid"]
    gid deploy_config["system"]["gid"]
    home deploy_config["system"]["home"]
    shell "/bin/bash"
    system true
  end

  directory deploy_config["system"]["home"] do
    owner deploy_config["system"]["user"]
    group deploy_config["system"]["group"]
    mode 0700
  end

end

#
# chown the entire install directory to app user
#

define :chown_install_directory, :name => nil, :deploy_config => nil do

  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  # directory "#{deploy_config["install"]["path"]}"
  # directory "#{deploy_config["install"]["path"]}/releases"

  bash "#{deploy_config["install"]["path"]} permissions" do
    user "root"
    cwd "/opt"
    code <<-EOH
    (chown -R #{deploy_config["system"]["user"]}:#{deploy_config["system"]["group"]} #{deploy_config["install"]["path"]})
    EOH
  end

end

#
# setup log dir
#

define :log_directory, :name => nil, :deploy_config => nil do

  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  directory "/var/log/#{deploy_config["id"]}" do
    owner deploy_config["system"]["user"]
    group deploy_config["system"]["group"]
  end

end

#
# setup additional directories
#

define :additional_directories, :name => nil, :deploy_config => nil do

  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  if deploy_config["config"]["additional_directories"]
    deploy_config["config"]["additional_directories"].each do |dir|
      directory dir do
        owner deploy_config["system"]["user"]
        group deploy_config["system"]["group"]
        mode 0755
        recursive true
      end
    end
  end

end

#
# any additional configs listed in the databag
#

define :additional_configs, :name => nil, :deploy_config => nil, :app_options => nil do

  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  # make sure the etc dir exists

  directory "#{deploy_config["install"]["path"]}/etc" do
    owner deploy_config["system"]["user"]
    group deploy_config["system"]["group"]
  end

  if deploy_config["config"]["additional_config_templates"]
    deploy_config["config"]["additional_config_templates"].each do |config|
      template "#{deploy_config["install"]["path"]}/etc/#{config}" do
        source "#{config}.erb"
        owner deploy_config["system"]["user"]
        group deploy_config["system"]["group"]
        mode 0644
        variables :deploy_config => deploy_config, :app_options => params[:app_options]
        notifies :restart, resources(:service => "#{deploy_config["id"]}")
      end
    end
  end

end

#
# additional bins listed in the databag
#

define :additional_binaries, :name => nil, :deploy_config => nil, :app_options => nil do

  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  # make sure the bin dir exists

  directory "#{deploy_config["install"]["path"]}/bin" do
    owner deploy_config["system"]["user"]
    group deploy_config["system"]["group"]
  end

  if deploy_config["config"]["additional_bin_templates"]
    deploy_config["config"]["additional_bin_templates"].each do |config|
      template "#{deploy_config["install"]["path"]}/bin/#{config}" do
        source "#{config}.erb"
        owner deploy_config["system"]["user"]
        group deploy_config["system"]["group"]
        mode 0755
        variables :deploy_config => deploy_config, :app_options => params[:app_options]
      end
    end
  end

end

#
# the start script (bin/APPID)
#

define :start_script, :name => nil, :deploy_config => nil, :app_options => nil do

  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  template "#{deploy_config["install"]["path"]}/bin/#{deploy_config["id"]}" do
    source "start.erb"
    owner deploy_config["system"]["user"]
    group deploy_config["system"]["group"]
    mode 0755
    variables :deploy_config => deploy_config, :app_options => params[:app_options]
    #notifies :restart, resources(:service => "#{deploy_config["id"]}")
  end

end

#
# iptables if needed
#

define :iptables, :name => nil, :deploy_config => nil do

  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  if deploy_config["config"]["iptables"]
    iptables_rule "10#{deploy_config["id"]}" do
      source "iptables_rules.erb"
    end
  end

end

#
# ssh and git keys
#

define :git_setup, :name => nil, :deploy_config => nil, :app_options => nil do

  if params[:deploy_config]
    deploy_config = params[:deploy_config]
  else
    deploy_config =  data_bag_item("apps", params[:name])
  end

  # make sure the etc dir exists

  directory "#{deploy_config["install"]["path"]}/etc" do
    owner   deploy_config["system"]["user"]
    group   deploy_config["system"]["group"]
  end

  template "#{deploy_config["install"]["path"]}/etc/git_ssh.sh" do
    source  "git_ssh.sh.erb"
    owner   deploy_config["system"]["user"]
    group   deploy_config["system"]["group"]
    mode    0755
    variables :deploy_config => deploy_config, :app_options => params[:app_options]
  end

  %w[ gitconfig deploy_key deploy_key.pub ].each do |filename|
    template "#{deploy_config["install"]["path"]}/etc/#{filename}" do
      source  "#{filename}.erb"
      owner   deploy_config["system"]["user"]
      group   deploy_config["system"]["group"]
      mode    0600
      variables :deploy_config => deploy_config, :app_options => params[:app_options]
    end
  end

end
