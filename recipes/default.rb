case node[:platform]
  when "ubuntu"
    apt_repository "erlang-solutions" do
      uri "http://packages.erlang-solutions.com/debian"
      distribution "precise"
      key "http://packages.erlang-solutions.com/debian/erlang_solutions.asc"
      components ["contrib"]
      action :add
    end
    
    execute "apt-get-update-periodic" do
      command "apt-get update"
      ignore_failure true
    end

    package "erlang" do
      if node[:erlang][:version] != :latest
        version node[:erlang][:version]
      end
    end
end
