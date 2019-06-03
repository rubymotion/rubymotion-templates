# encoding: utf-8

require 'pathname'

class Glob
  # Apple introducted a new file system in High Sierra (UTF-8).
  # Mac OS Extended was UTF-16 and the ruby source code `dir.c` explicitly
  # assumes UTF-16 for the __APPLE__ compiler flag (which as been the
  # case for the past 30 years until 2018). This causes Dir.glob to #
  # return a different file order on High Sierra vs Sierra. This
  # method is a # compatible version of Dir.glob from Sierra and is
  # used by RM to load ruby and header files in lexicographical order.
  # See: https://developer.apple.com/library/content/documentation/FileManagement/Conceptual/APFS_Guide/FAQ/FAQ.html
  # and: https://github.com/ruby/ruby/blob/trunk/dir.c#L120
  # for more info.
  def self.lexicographically pattern
    supported_extensions = %w( c m cpp cxx mm h rb)
    pathnames = Pathname.glob pattern
    pathnames.sort_by do |p|
      p.each_filename.to_a.map(&:downcase).unshift supported_extensions.index(p.to_s.split(".").last)
    end.map { |p| p.to_s }
  end
end
