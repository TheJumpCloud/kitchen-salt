module Kitchen
  module Salt
    module Mine
      private

      def get_mine_data
        info('Collecting mine data')

        # Read in all the data from the mine files first
        mine_from_files = config[:'mine-from-files']
        debug("Mine Files: #{mine_from_files}")
        data = mine_from_files.inject({}) do |memo, file|
          puts "file: #{file.inspect}"
          memo.merge(YAML.load_file(file))
          # TODO(ppg): consider catching and generating a better error message
        end

        # Then load data from the mine key
        mine = config[:mine]
        debug("Mine Hash: #{mine}")
        data.merge(config[:mine] || {})
      end

      def prepare_mines_files(mines)
        mines.each do |key, contents|
          # convert the hash to yaml
          mine = contents.to_yaml

          # .to_yaml will produce ! '*' for a key, Salt doesn't like this either
          mine.gsub!(/(!\s'\*')/, "'*'")

          # generate the filename
          sandbox_mine_path = File.join(sandbox_path, config[:salt_mine_root], key)

          debug("Rendered mine yaml for #{key}:\n #{mine}")
          write_raw_file(sandbox_mine_path, mine)
        end
      end

      def copy_mine(key, srcfile)
        debug("Copying external mine: #{key}, #{srcfile}")
        # generate the filename
        sandbox_mine_path = File.join(sandbox_path, config[:salt_mine_root], key)
        # create the directory where the mine file will go
        FileUtils.mkdir_p(File.dirname(sandbox_mine_path))
        # copy the file across
        FileUtils.copy srcfile, sandbox_mine_path
      end

      def prepare_mines_from_files(mines)
        external_mines = unsymbolize(mines)
        debug("external_mines (unsymbolize): #{external_mines}")
        external_mines.each do |key, srcfile|
          copy_mine(key, srcfile)
        end
      end
    end
  end
end
