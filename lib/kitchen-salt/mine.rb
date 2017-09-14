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
          memo.merge(YAML.load_file(file))
          # TODO(ppg): consider catching and generating a better error message on parsing issue
        end

        # Then load data from the mine key
        mine = config[:mine]
        debug("Mine Hash: #{mine}")
        data.merge(config[:mine] || {})
      end
    end
  end
end
