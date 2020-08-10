#!/usr/bin/env ruby
# Parse School Committee agendas
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

module SchoolParser
  DESCRIPTION = <<-HEREDOC
  AgendaParser: Parse School Committee agendas with times, but not item numbers
  HEREDOC
  extend self
  require 'nokogiri'
  require_relative 'agendautils'
  
  # Parse a School Committee agenda page and output array of hashes of semi-structured data
  # This is customized to the specific School Committee agenda formats from 2020
  # @param io stream to read
  # @param id identifier of stream (filename or URL)
  # @param parentid for anchors
  # @return data hash listing agenda metadata and details; includes AgendaUtils::ERROR key if any
  def parse(io, id, parentid)
    data = {}
    begin
      doc = Nokogiri::HTML(io)
      tables = doc.css('td > table') # All tables inside a cell
      AgendaUtils.log("#{__method__.to_s}() Parsing agenda table rows: #{tables.length} for #{id}")
      raise ArgumentError.new("Agenda data not found; perhaps meeting was cancelled?") if tables.length < 3
      # Grab header info from first table
      data[AgendaUtils::NOTICE] = tables.shift.css("[colspan]#column1").text.strip
      # Second table is spacer
      tables.shift
      # Third table is additional meeting notice stuff
      data[AgendaUtils::NOTICE] = tables.shift.css("[colspan]#column1").text.strip
      # Fourth table is spacer - again
      tables.shift
      # Process all remaining tables depending on cell contents (order may be random or repeated)
      data[AgendaUtils::ITEMS] = []
      tables.each do |t|
        next if t.css('.style2').any? # Drop any with style2, those are spacers
        item = parse_row(t, parentid)
        data[AgendaUtils::ITEMS] << item if item
      end
    rescue StandardError => e
      data[AgendaUtils::ERROR] = "#{id} #{e.message}"
      data[AgendaUtils::STACK] = e.backtrace.join("\n\t")
    end
    return data
  end
  
  # Parse a single "row" (a sub <table>) element of a School Committee agenda
  # @param table element
  # @return hash of data; or nil if blank spacer
  def parse_row(table, parentid)
    item = {}
    # Parse all style1 - seems to be only one used?
    cells = table.css('.style1')
    blobs = ''
    links = []
    cells.each do |cell|
      # Recursively parse only nodes that are interesting
      next if cell.text?
      cell.children.each do |node|
        parse_node(node, blobs, links)
      end
      blobs << "\n\n" # Ensure each td cell is a separate line
    end
    if blobs.empty?
      return nil
    else
      item['urls'] = links if links.any?
      # Attempt to trim unneeded blank lines and excess space
      item[AgendaUtils::DETAILS] = blobs.gsub(AgendaUtils::NBSP, ' ').gsub(/\n\s+\n/, "\n\n").gsub(/\n{3,8}/, "\n\n").gsub(/\n\s{3,}/, "\n ")
      return item
    end
  end
 
  LOCAL_PREFIX = '<a href="https://arlington.novusagenda.com/Agendapublic/'
  FULL_PREFIX = '<a href="'
  # Recursively parse contents of a td cell or p element
  # @param node of td cell
  # @param blobs string to aggregate any markdown to
  # @param links array to aggregate any hrefs to
  def parse_node(node, blobs, links)
    if node.text?
      blobs << node.content.strip unless node.content.strip.empty?
    else
      # Process elements
      case node.name
      when 'a'
        links << node['href']
        /http/ =~ node['href'] ? blobs.concat(FULL_PREFIX, node['href'], '">') : blobs.concat(LOCAL_PREFIX, node['href'], '">')
        blobs << "#{node.content.strip}</a> "
      when 'p'
        node.children.each do |child|
          parse_node(child, blobs, links)
        end
        blobs << "  \n" # Use GFM
      when 'ul'
        parse_ul(node, blobs, links)
      else
        # No-op: ignore other nodes; either not needed or we already got contents
      end # case
    end # if
  end

  # Parse just a flat ul element (grabbing text from each li)
  # @param node of ul cell
  # @param blobs string to aggregate any markdown to
  # @param links array to aggregate any hrefs to
  def parse_ul(node, blobs, links)
    blobs << "\n" # Ensure markdown treats as list
    node.children.each do |child|
      if 'li'.eql?(child.name)
        blobs << "\n- #{child.content.strip}" unless child.content.strip.empty?
      end
    end
    blobs << "\n\n" # Ensure markdown treats as list
  end
end

