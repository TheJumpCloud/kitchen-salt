
#
# Author:: Simon McCartney <simon.mccartney@hp.com>
#
# Copyright (C) 2013, Chris Lundquist, Simon McCartney
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fileutils'
require 'hashie'
require 'kitchen-salt/pillars'
require 'kitchen-salt/states'
require 'kitchen-salt/util'
require 'kitchen/provisioner/base'
require 'yaml'

module Kitchen
  module Provisioner
    # Basic Salt Masterless Provisioner, based on work by
    #
    # @author Chris Lundquist (<chris.ludnquist@github.com>)

    class SaltSolo < Base
      include Kitchen::Salt::Util
      include Kitchen::Salt::Pillars
      include Kitchen::Salt::States

      DEFAULT_CONFIG = {
        bootstrap_url: 'https://raw.githubusercontent.com/saltstack/kitchen-salt/master/assets/install.sh',
        chef_bootstrap_url: 'https://www.getchef.com/chef/install.sh',
        dependencies: [],
        dry_run: false,
        install_after_init_environment: false,
        is_file_root: false,
        local_salt_root: nil,
        omnibus_cachier: false,
        pillars_from_directories: [],
        pip_bin: 'pip',
        pip_editable: false,
        pip_extra_index_url: [],
        pip_index_url: 'https://pypi.python.org/simple/',
        pip_pkg: 'salt==%s',
        remote_states: nil,
        require_chef: true,
        salt_apt_repo_key: 'https://repo.saltstack.com/apt/ubuntu/16.04/amd64/latest/SALTSTACK-GPG-KEY.pub',
        salt_apt_repo: 'https://repo.saltstack.com/apt/ubuntu/16.04/amd64/',
        salt_bootstrap_options: '',
        salt_bootstrap_url: 'https://bootstrap.saltstack.com',
        salt_config: '/etc/salt',
        salt_copy_filter: [],
        salt_env: 'base',
        salt_file_root: '/srv/salt',
        salt_force_color: false,
        salt_install: 'bootstrap',
        salt_minion_config_dropin_files: [],
        salt_minion_config_template: nil,
        salt_minion_config: '/etc/salt/minion',
        salt_minion_extra_config: {},
        salt_minion_id: nil,
        salt_pillar_root: '/srv/pillar',
        salt_ppa: 'ppa:saltstack/salt',
        salt_spm_root: '/srv/spm',
        salt_state_top: '/srv/salt/top.sls',
        salt_version: 'latest',
        salt_yum_repo_key: 'https://repo.saltstack.com/yum/redhat/$releasever/$basearch/archive/%s/SALTSTACK-GPG-KEY.pub',
        salt_yum_repo_latest: 'https://repo.saltstack.com/yum/redhat/salt-repo-latest-2.el7.noarch.rpm',
        salt_yum_repo: 'https://repo.saltstack.com/yum/redhat/$releasever/$basearch/archive/%s',
        salt_yum_rpm_key: 'https://repo.saltstack.com/yum/redhat/7/x86_64/archive/%s/SALTSTACK-GPG-KEY.pub',
        state_collection: false,
        state_top_from_file: false,
        state_top: {},
        vendor_path: nil,
        vendor_repo: {}
      }.freeze

      # salt-call version that supports the undocumented --retcode-passthrough command
      RETCODE_VERSION = '0.17.5'.freeze

      DEFAULT_CONFIG.each do |k, v|
        default_config k, v
      end

      def install_command
        unless config[:salt_install] == 'pip' || config[:install_after_init_environment]
          setup_salt
        end
      end

      def prepare_command
        if config[:salt_install] == 'pip' || config[:install_after_init_environment]
          setup_salt
        end
      end

      def setup_salt
        debug(diagnose)
        salt_version = config[:salt_version]

        # if salt_verison is set, bootstrap is being used & bootstrap_options is empty,
        # set the bootstrap_options string to git install the requested version
        if (salt_version != 'latest') && (config[:salt_install] == 'bootstrap') && config[:salt_bootstrap_options].empty?
          debug("Using bootstrap git to install #{salt_version}")
          config[:salt_bootstrap_options] = "-P git v#{salt_version}"
        end

        install_template = if windows_os?
                             File.expand_path('./../install_win.erb', __FILE__)
                           else
                             File.expand_path('./../install.erb', __FILE__)
                           end

        erb = ERB.new(File.read(install_template)).result(binding)
        debug('Install Command:' + erb.to_s)
        erb
      end

      def install_chef
        return unless config[:require_chef]
        chef_url = config[:chef_bootstrap_url]
        if windows_os?
          <<-POWERSHELL
            if (-Not $(test-path c:\\opscode\\chef) {
              if (-Not $(Test-Path c:\\temp)) {
                New-Item -Path c:\\temp -itemtype directory
              }
              (New-Object net.webclient).DownloadFile("#{chef_url}", "c:\\temp\\chef_bootstrap.ps1")
              write-host "-----> Installing Chef Omnibus (for busser/serverspec ruby support)"
              #{sudo('powershell')} c:\\temp\\chef_bootstrap.ps1
            }
          POWERSHELL
        else
          omnibus_download_dir = config[:omnibus_cachier] ? '/tmp/vagrant-cache/omnibus_chef' : '/tmp'
          bootstrap_url = config[:bootstrap_url]
          bootstrap_download_dir = '/tmp'
          <<-INSTALL
              echo "-----> Trying to install ruby(-dev) using assets.sh from kitchen-salt"
                mkdir -p #{bootstrap_download_dir}
                if [ ! -x #{bootstrap_download_dir}/install.sh ]
                then
                  do_download #{bootstrap_url} #{bootstrap_download_dir}/install.sh
                fi
                #{sudo('sh')} #{bootstrap_download_dir}/install.sh -d #{bootstrap_download_dir}
              if [ $? -ne 0 ] || [ ! -d "/opt/chef" ]
              then
                echo "Failed install ruby(-dev) using assets.sh from kitchen-salt"
                echo "-----> Fallback to Chef Bootstrap script (for busser/serverspec ruby support)"
                mkdir -p "#{omnibus_download_dir}"
                if [ ! -x #{omnibus_download_dir}/install.sh ]
                then
                    #{sudo('sh')} #{omnibus_download_dir}/install.sh -d #{omnibus_download_dir}
                fi;
              fi
          INSTALL
        end
      end

      def create_sandbox
        super
        prepare_data
        prepare_install
        prepare_minion
        prepare_pillars
        prepare_grains
        prepare_states
        prepare_state_top
        # upload scripts, cached formulas, and setup system repositories
        prepare_dependencies
      end

      def prepare_install
        salt_version = config[:salt_version]
        if config[:salt_install] == 'pip'
          debug('Using pip to install')
          if File.exist?(config[:pip_pkg])
            debug('Installing with pip from sdist')
            sandbox_pip_path = File.join(sandbox_path, 'pip')
            FileUtils.mkdir_p(sandbox_pip_path)
            FileUtils.cp_r(config[:pip_pkg], sandbox_pip_path)
            config[:pip_install] = File.join(config[:root_path], 'pip', File.basename(config[:pip_pkg]))
          else
            debug('Installing with pip from download')
            if salt_version != 'latest'
              config[:pip_install] = format(config[:pip_pkg], salt_version)
            else
              config[:pip_pkg].slice!('==%s')
              config[:pip_install] = config[:pip_pkg]
            end
          end
        elsif config[:salt_install] == 'bootstrap'
          if File.exist?(config[:salt_bootstrap_url])
            FileUtils.cp_r(config[:salt_bootstrap_url], File.join(sandbox_path, 'bootstrap.sh'))
          end
        end
      end

      def init_command
        debug("Initialising Driver #{name}")
        cmd = if windows_os?
                'mkdir -Force -Path '"#{config[:root_path]}""\n"
              else
                "mkdir -p '#{config[:root_path]}';"
              end
        cmd += <<-INSTALL
          #{config[:init_environment]}
        INSTALL
        cmd
      end

      def salt_command
        salt_version = config[:salt_version]

        cmd = ''
        if windows_os?
          salt_call = 'c:\\salt\\salt-call.bat'
          salt_config_path = config[:salt_config].tr('/', '\\')
          cmd << "(get-content #{File.join(config[:root_path], salt_config_path, 'minion').tr('/', '\\')}).replace(\"`$env`:TEMP\", $env:TEMP) | set-content #{File.join(config[:root_path], salt_config_path, 'minion').tr('/', '\\')} ;"
        else
          # install/update dependencies
          cmd << sudo("chmod +x #{config[:root_path]}/*.sh;")
          cmd << sudo("#{config[:root_path]}/dependencies.sh;")
          salt_config_path = config[:salt_config]
          salt_call = 'salt-call'
        end
        cmd << sudo("#{salt_call} --state-output=changes --config-dir=#{File.join(config[:root_path], salt_config_path)} --local state.highstate")
        cmd << " --log-level=#{config[:log_level]}" if config[:log_level]
        cmd << " --id=#{config[:salt_minion_id]}" if config[:salt_minion_id]
        cmd << " test=#{config[:dry_run]}" if config[:dry_run]
        cmd << ' --force-color' if config[:salt_force_color]
        if salt_version > RETCODE_VERSION || salt_version == 'latest'
          # hope for the best and hope it works eventually
          cmd << ' --retcode-passthrough'
        end
        cmd << ' ; exit $LASTEXITCODE' if windows_os?
        cmd
      end

      def run_command
        debug("running driver #{name}")
        debug(diagnose)

        # config[:salt_version] can be 'latest' or 'x.y.z', 'YYYY.M.x' etc
        # error return codes are a mess in salt:
        #  https://github.com/saltstack/salt/pull/11337
        # Unless we know we have a version that supports --retcode-passthrough
        # attempt to scan the output for signs of failure
        if config[:salt_version] <= RETCODE_VERSION
          # scan the output for signs of failure, there is a risk of false negatives
          fail_grep = 'grep -e Result.*False -e Data.failed.to.compile -e No.matching.sls.found.for'
          # capture any non-zero exit codes from the salt-call | tee pipe
          cmd = 'set -o pipefail ; ' << salt_command
          # Capture the salt-call output & exit code
          cmd << ' 2>&1 | tee /tmp/salt-call-output ; SC=$? ; echo salt-call exit code: $SC ;'
          # check the salt-call output for fail messages
          cmd << " (sed '/#{fail_grep}/d' /tmp/salt-call-output | #{fail_grep} ; EC=$? ; echo salt-call output grep exit code ${EC} ;"
          # use the non-zer exit code from salt-call, then invert the results of the grep for failures
          cmd << ' [ ${SC} -ne 0 ] && exit ${SC} ; [ ${EC} -eq 0 ] && exit 1 ; [ ${EC} -eq 1 ] && exit 0)'
          cmd
        else
          salt_command
        end
      end

      protected

      def prepare_data
        return unless config[:data_path]

        info('Preparing data')
        debug("Using data from #{config[:data_path]}")

        tmpdata_dir = File.join(sandbox_path, 'data')
        FileUtils.mkdir_p(tmpdata_dir)
        cp_r_with_filter(config[:data_path], tmpdata_dir, config[:salt_copy_filter])
      end

      def prepare_minion_base_config
        if config[:salt_minion_config_template]
          minion_template = File.expand_path(config[:salt_minion_config_template], Kitchen::Config.new.kitchen_root)
        else
          minion_template = File.expand_path('./../minion.erb', __FILE__)
        end

        minion_config_content = if File.extname(minion_template) == '.erb'
                                  ERB.new(File.read(minion_template)).result(binding)
                                else
                                  File.read(minion_template)
                                end

        # create the temporary path for the salt-minion config file
        debug("sandbox is #{sandbox_path}")
        sandbox_minion_config_path = File.join(sandbox_path, config[:salt_minion_config])

        write_raw_file(sandbox_minion_config_path, minion_config_content)
      end

      def prepare_minion_extra_config
        minion_template = File.expand_path('./../99-minion.conf.erb', __FILE__)

        safe_hash = Hashie.stringify_keys(config[:salt_minion_extra_config])
        minion_extra_config_content = ERB.new(File.read(minion_template)).result(binding)

        sandbox_dropin_path = File.join(sandbox_path, 'etc/salt/minion.d')

        write_raw_file(File.join(sandbox_dropin_path, '99-minion.conf'), minion_extra_config_content)
      end

      def insert_minion_config_dropins
        sandbox_dropin_path = File.join(sandbox_path, 'etc/salt/minion.d')
        Dir.mkdir(sandbox_dropin_path)

        config[:salt_minion_config_dropin_files].each_index do |i|
          filename = File.basename(config[:salt_minion_config_dropin_files][i])
          index = (99 - config[:salt_minion_config_dropin_files].count + i).to_s.rjust(2, '0')

          file = File.expand_path(config[:salt_minion_config_dropin_files][i])
          data = File.read(file)

          write_raw_file(File.join(sandbox_dropin_path, [index, filename].join('-')), data)
        end
      end

      def prepare_minion
        info('Preparing salt-minion')
        prepare_minion_base_config
        prepare_minion_extra_config if config[:salt_minion_extra_config].keys.any?
        insert_minion_config_dropins if config[:salt_minion_config_dropin_files].any?
      end

      def prepare_grains
        debug("Grains Hash: #{config[:grains]}")

        return if config[:grains].nil?

        info("Preparing grains into #{config[:salt_config]}/grains")

        # generate the filename
        sandbox_grains_path = File.join(sandbox_path, config[:salt_config], 'grains')
        debug("sandbox_grains_path: #{sandbox_grains_path}")

        write_hash_file(sandbox_grains_path, config[:grains])
      end

      def prepare_dependencies
        # upload scripts
        sandbox_scripts_path = File.join(sandbox_path, config[:salt_config], 'scripts')
        info("Preparing scripts into #{config[:salt_config]}/scripts")

        # PLACEHOLDER, git formulas might be fetched locally to temp and uploaded

        # setup spm
        spm_template = File.expand_path('./../spm.erb', __FILE__)
        spm_config_content = ERB.new(File.read(spm_template)).result(binding)
        sandbox_spm_config_path = File.join(sandbox_path, config[:salt_config], 'spm')
        write_raw_file(sandbox_spm_config_path, spm_config_content)

        spm_repos = config[:vendor_repo].select { |x| x[:type] == 'spm' }.each { |x| x[:url] }.map { |x| x[:url] }
        spm_repos.each do |url|
          id = url.gsub(/[htp:\/.]/, '')
          spmreposd = File.join(sandbox_path, 'etc', 'salt', 'spm.repos.d')
          repo_spec = File.join(spmreposd, 'spm.repo')
          FileUtils.mkdir_p(spmreposd)
          repo_content = "
#{id}:
  url: #{url}
"
          write_raw_file(repo_spec, repo_content)
        end

        # upload scripts
        %w[formula-fetch.sh repository-setup.sh].each do |script|
          write_raw_file(File.join(sandbox_path, script), File.read(File.expand_path("../#{script}", __FILE__)))
        end
        dependencies_script = File.expand_path('./../dependencies.erb', __FILE__)
        dependencies_content = ERB.new(File.read(dependencies_script)).result(binding)
        write_raw_file(File.join(sandbox_path, 'dependencies.sh'), dependencies_content)
      end
    end
  end
end
