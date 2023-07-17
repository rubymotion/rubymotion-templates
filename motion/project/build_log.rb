module Motion
  class BuildLog
    def self.lock
      @lock ||= Mutex.new
      @lock
    end

    def self.begin!
      @output_directory = File.join `pwd`.strip, 'build-log'
      @temp_directory   = File.join @output_directory, 'tmp'

      FileUtils.rm_r    @temp_directory if Dir.exist? @temp_directory
      FileUtils.mkdir_p @output_directory
      FileUtils.mkdir_p @temp_directory

      @log_id = 10000
      @lock = Mutex.new
    end

    def self.end!
      build_log_txt = File.join @output_directory, 'build-log.txt'
      File.write build_log_txt, ''
      File.open build_log_txt, 'a' do |f|
        Dir.glob(File.join @temp_directory, 'log-*').sort.each do |t|
          temp_file_contents = File.read t
          temp_file_contents += "\n" if !temp_file_contents.end_with? "\n"
          f.write temp_file_contents
        end
      end
    end

    def self.to_s_dwim thing
      return thing if thing.is_a? String
      if thing.is_a? Enumerable
        return thing.map do |i|
          "- #{i}"
        end.join "\n"
      end
    end

    def self.defaults_org
      {
        topic:      '',
        type:       :h1,
        title:      'TITLE',
        properties: nil,
        text:       ''
      }
    end

    def self.topic_id!
      @lock.synchronize do
        @log_id += 1000
        @log_id
      end
    end

    def self.org opts
      opts       = defaults_org.merge opts
      title      = opts[:title]
      text       = opts[:text]
      properties = opts[:properties]
      topic_id   = opts[:topic_id]
      topic_name = opts[:topic_name]

      if text.is_a? Enumerable
        text = text.map { |i| to_s_dwim i }.join "\n"
      end

      case opts[:type]
      when :h1
        tab_level = 0
      when :h2
        tab_level = 1
      when :h3
        tab_level = 2
      when :h4
        tab_level = 3
      when :h5
        tab_level = 4
      when :h6
        tab_level = 5
      else
        tab_level = 0
      end

      asterisk = "*" * (tab_level + 1)
      leading_spaces = tab_level + 2
      title_string = "#{asterisk} #{title}\n"
      properties_string = __org_properties_string__ properties, leading_spaces
      final_string = title_string + properties_string + text
      write final_string, topic_id, topic_name
    end

    def self.format_src opts
      type = opts[:type]
      text = opts[:text]
      text = text.map { |l| l.to_s.strip }.join "\n" if text.is_a? Array
      text = text.each_line.map { |l| "  #{l.strip}" }.join "\n"
      <<~S
      #+begin_src #{type}
      #{text}
      #+end_src
      S
    end

    def self.__org_properties_string__ properties, leading_spaces
      return '' unless properties
      return '' unless properties.keys.length > 0
      properties_string = properties.map do |k, v|
        formatted_v = v
        formatted_v = v.strftime('%H:%M:%S.%L') if v.is_a? Time
        formatted_v = ":#{v}" if v.is_a? Symbol
        ":#{k}: #{formatted_v}"
      end.join "\n"

      return <<~S.each_line.map { |l| "#{' ' * leading_spaces}#{l}" }.join
      :PROPERTIES:
      #{properties_string}
      :END:
      S
    end

    def self.write s, topic_id = nil, topic_name = nil
      @lock.synchronize do
        @log_id += 1
        topic_id ||= @log_id
        log_number_s = "#{topic_id.to_s.rjust(3, padstr='0')}-#{@log_id.to_s.rjust(3, padstr='0')}"
        temp_path = "log-#{log_number_s}"
        temp_file = File.join @temp_directory, temp_path
        File.write(temp_file, '')
        File.open(temp_file, 'a') do |f|
          f.write s
        end

        if topic_name
          temp_path = "log-#{log_number_s}-#{topic_name}"
          temp_file = File.join @output_directory, temp_path
          File.write(temp_file, '')
          File.open(temp_file, 'a') do |f|
            f.write s
          end
        end
      end
    end
  end
end
