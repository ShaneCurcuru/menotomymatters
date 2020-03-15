#!/usr/bin/env ruby
# Simplistic spider for gathering links
# Copyright (c) 2020 Shane Curcuru
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

module Spyder
  DESCRIPTION = <<-HEREDOC
  Spyder: Parse URLs and save various links
  HEREDOC
  extend self
  require 'nokogiri'
  require 'open-uri'
  require 'json'
  require 'optparse'

  TEST_URL = 'https://www.minlib.net/our-libraries'
  MINLIB_HOST = 'https://www.minlib.net'

  # Parse minlib listing and output list of libraries
  # @param url to read
  # @param type to assign
  # @return data hash of one library
  def parse_library(url, type)
    data = {}
    begin
      doc = Nokogiri::HTML(open(url))
      library = doc.css('.library')
      data['status'] = 'closed' # Default, for manual editing
      data['type'] = type
      nodelist = library.css('.library-name-and-details > h1')
      data['name'] = nodelist[0].text.strip if nodelist[0]
      nodelist = library.css('.field--name-field-library-description')
      data['description'] = nodelist[0].text.strip if nodelist[0]
      nodelist = library.css('.library-address > div')
      data['address'] = nodelist[0].text.squeeze(' ').strip.split("\n").join(',') if nodelist[0]
      nodelist = library.css('.library-telephone-numbers > div')
      data['telephone'] = nodelist[0].text.strip if nodelist[0]
      nodelist = library.css('.library-website a')
      data['url'] = nodelist[0]['href'] if nodelist[0]
      nodelist = library.css('.twitter-timeline')
      data['twitterurl'] = nodelist[0]['href'] if nodelist[0]
      nodelist = library.css('.btn-success')
      data['hoursurl'] = nodelist[0]['href'] if nodelist[0]
    rescue StandardError => e
      data['error'] = "#{e.message}\n\n#{e.backtrace.join("\n\t")}"
    end
    return data
  end


  # Parse minlib listing and output list of libraries
  # @param url to read
  # @return data hash
  def parse_minlib(url)
    data = {}
    data['libraries'] = {}
    doc = Nokogiri::HTML(open(url))
    listings = doc.css('.view-content')
    type = 'public'
    listings.each do |list|
      # Grab any href that starts with /
      ourlibs = list.css('a')
      ourlibs.each do |lib|
        if lib['href'].start_with?('/')
          data['libraries'][lib.text] = parse_library(File.join(MINLIB_HOST, lib['href']), type)
        end
      end
      type = 'academic' # HACK: relies on there being two listings in order
    end
    return data
  end
  
  # Just resort previously parsed data
  def sortlist(file)
    data = []
    JSON.parse(File.read(file)).each do |k, hsh|
      hsh['title'] = k
      data << hsh
    end
    return data
  end

  # ### #### ##### ######
  # Main method for command line use
  if __FILE__ == $PROGRAM_NAME
    url = TEST_URL
    outfile = 'libraries.json'
###    puts "Parsing #{url}"
###    data = parse_minlib(url)
    data = sortlist(outfile)
    File.open(outfile, 'w') do |f|
      f.puts JSON.pretty_generate(data)
    end
    puts "Done, output #{outfile}"
  end
end

