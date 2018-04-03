module Kitchen
  module Salt
    module Mock
      private

      def prepare_mock
        info('Preparing mock setup')
        %w[_states/mock.py mock/mine.sls mock/remote_functions.sls].each do |file|
          mock_source = File.expand_path(File.join('./../../kitchen/provisioner', file), __FILE__)
          target = File.join(sandbox_path, config[:salt_file_root], file)
          subdir_path = File.dirname(target)
          FileUtils.mkdir_p(subdir_path)
          debug("  ...#{file}")
          FileUtils.cp mock_source, target
        end

        # Copy over mock remote functions
        prepare_mine
        prepare_remote_functions
      end

      def prepare_mine
        info("Preparing mine into #{config[:salt_mock_mine_root]}")
        subdir_path = File.join(sandbox_path, config[:salt_mock_mine_root])
        FileUtils.mkdir_p(subdir_path)
        file = config[:'mock-mine']
        debug("  ...#{file}")
        FileUtils.copy file, File.join(subdir_path, file)
      end

      def prepare_remote_functions
        info("Preparing remote_functions into #{config[:salt_mock_remote_functions_root]}")
        subdir_path = File.join(sandbox_path, config[:salt_mock_remote_functions_root])
        FileUtils.mkdir_p(subdir_path)
        file = config[:'mock-remote-functions']
        debug("  ...#{file}")
        FileUtils.copy file, File.join(subdir_path, file)
      end

      def get_mock_mine_data
        return unless config[:'mock-mine']
        info("Collecting mock mine data from #{config[:'mock-mine']}")
        YAML.load_file(config[:'mock-mine'])
      end
    end
  end
end
