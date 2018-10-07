# encoding: utf-8

# Copyright (c) 2018, Scratchwork Development,
#                     CANA Software & Services (Andy Stechishin) and contributors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'json'

IosIconDefinition = Struct.new(:idiom, :size, :scale) do
  def file_name
    image_square_string + (idiom == :ipad ? '~ipad' : '') +
        (scale > 1 ? "@%dx" % scale : "") + ".png"
  end

  def image_size
    size * scale
  end

  def image_square_string
    size == size.to_i ? "%2dx%2d" % [size, size] : "%2.1fx%2.1f" % [size, size]
  end

  def image_hash
    {idiom: idiom, size: image_square_string, filename: file_name, scale: "%dx" % scale}
  end
end

rule '.icon_asset' => '.png' do |t|
  icon_dir = File.dirname(t.source) + '/Assets.xcassets/AppIcon.appiconset'
  tmp_file = File.dirname(t.source) + '/' + File.basename(t.source, '.png') + '.icon_asset'
  mkdir_p icon_dir

  Dir.glob(File.join(icon_dir, '*.png')).each { |f| rm f }

  ios_icon_list.each do |icon_defn|
    sh "sips -Z #{icon_defn.image_size}  #{t.source} --out #{icon_dir}/#{icon_defn.file_name}"
  end

  File.open(icon_dir + "/Contents.json", 'w') do |f|
    content_structure = {
        images: ios_icon_list.map { |icon_defn| icon_defn.image_hash },
        info: {version: 1, author: 'xcode'}
    }
    f << JSON.pretty_generate(content_structure, indent: '  ', space: ' ', space_before: ' ')
  end

  touch tmp_file
end

def ios_icon_list
  [
      IosIconDefinition.new(:iphone, 20, 2),
      IosIconDefinition.new(:iphone, 20, 3),
      IosIconDefinition.new(:iphone, 29, 2),
      IosIconDefinition.new(:iphone, 29, 3),
      IosIconDefinition.new(:iphone, 40, 2),
      IosIconDefinition.new(:iphone, 40, 3),
      IosIconDefinition.new(:iphone, 60, 2),
      IosIconDefinition.new(:iphone, 60, 3),
      IosIconDefinition.new(:ipad, 20, 1),
      IosIconDefinition.new(:ipad, 20, 2),
      IosIconDefinition.new(:ipad, 29, 1),
      IosIconDefinition.new(:ipad, 29, 2),
      IosIconDefinition.new(:ipad, 40, 1),
      IosIconDefinition.new(:ipad, 40, 2),
      IosIconDefinition.new(:ipad, 76, 2),
      IosIconDefinition.new(:ipad, 83.5, 2),
      IosIconDefinition.new('ios-marketing', 1024, 1)
  ]
end
