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
  
  # TODO Normalize, shared with SelectParser
  LOCAL_PREFIX = '<a href="https://arlington.novusagenda.com/Agendapublic/'
  FULL_PREFIX = '<a href="'
  LINK_POSTFIX = '"><i class="fa fa-fw fa-file-alt" aria-hidden="true"></i></a> '
  MAIL_POSTFIX = '"><i class="fa fa-fw fa-envelope" aria-hidden="true"></i></a> '
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
        puts "DEBUG: each: #{node.name} == #{node.content}"
        blobs << "\n"
        parse_node(node, blobs, links)
      end
    end
    if blobs.empty?
      return nil
    else
      item['xlinks'] = links
      item[AgendaUtils::DETAILS] = blobs
      return item
    end
  end
  
  # Recursively parse contents of a td cell or p element
  # @param node of td cell
  # @param blobs string to aggregate any markdown to
  # @param links array to aggregate any hrefs to
  def parse_node(node, blobs, links)
    debug = false
    debug = true if /Mistler/ =~ node.content
    if debug then
      puts "DEBUG: pn: #{node.name} == #{node.content}"
      puts "---------:"
      puts blobs
      puts ":---------"
    end
    if node.text?
      blobs << node.content.strip unless node.content.strip.empty?
    else
      # Process elements
      case node.name
      when 'a'
        links << node['href']
        blobs << "<a href='#{node['href']}'>#{node.content.strip}</a>"
      when 'p'
        node.children.each do |child|
          parse_node(child, blobs, links)
        end      
      when 'ul'
        parse_ul(node, blobs, links)
      else
        # No-op: ignore other nodes; either not needed or we already got contents
      end # case
    end # if
    if debug then
      puts "=DEBUG: pn: #{node.name} == #{node.content}"
      puts "---------:"
      puts blobs
      puts ":---------"
    end

  end

  # Parse just a flat ul element (grabbing text from each li)
  # @param node of ul cell
  # @param blobs string to aggregate any markdown to
  # @param links array to aggregate any hrefs to
  def parse_ul(node, blobs, links)
    blobs << "\n" # Ensure markdown treats as list
    node.children.each do |child|
      case child.name
      when 'li'
        blobs << "\n- #{child.content.strip}" unless child.content.strip.empty?
        next
      else
        # No-op: we only take the items
      end
    end
    blobs << "\n" # Ensure markdown treats as list
  end

  #require 'json'

  # if __FILE__ == $PROGRAM_NAME
  #   agenda = {}
  #   fn = 'schoolagenda.html'
  #   out = 'schoolagenda.json'
  #   puts "Shortcut: parsing #{fn} as a one-off into #{out} - debugging!"
  #   doc = Nokogiri::HTML(File.read(fn))
  #   tables = doc.css('td > table')
  #   blobs = ''
  #   links = []
  ### NEW WAY
  #   tables[10].children.each do |tr|
  #     next if tr.text?
  #     # Parse each TR's TD children
  #     tr.children.each do |td|
  #       next unless 'style1'.eql?(td['class'])
  #       td.children.each do |node|
  #         blobs << "\n"
  #         parse_node(node, blobs, links)
  #       end
  #     end
  #   end
  #   puts "Links: #{links.uniq}"
  #   puts "... blobs:"
  #   puts blobs
  #   exit 0
  #   agenda = parse(File.read(fn), fn, 'test9')
  #   File.open(out, "w") do |f|
  #     f.puts JSON.pretty_generate(agenda)
  #   end
  # end
        ### OLD WAY - hand-process each type
      # Process and remove any <a>
      # anchors = cell.css('a')
      # anchors.each do |a| # TODO Parse out any time refefence from the child text element and add a style to it
      #   if /mailto/ =~ a['href']
      #     blob.concat(FULL_PREFIX, a['href'], MAIL_POSTFIX)
      #   else
      #      blob.concat(/http/ =~ a['href'] ? FULL_PREFIX : LOCAL_PREFIX, a['href'], LINK_POSTFIX)
      #   end
      #   ### cell.remove(a)
      # end
      # # Process and remove any <ul>
      # lists = cell.css('ul')
      # lists.each do |ul|
      #   itms = ul.css('li')
      #   itms.each do |itm|
      #     blob.concat("\n", "- ", itm.text.strip)
      #   end
      #   ### cell.remove(lists)
      # end
      # # Aggregate any remaining text (in case there's unstructured text content)  
      # txt = cell.text.strip
      # blob.concat(txt.gsub("\r\n", "\n"), "\n\n")
      # unless blob.empty?
      #   item[AgendaUtils::DETAILS] = blob
      #   item['nextmtg'] = true if blob.start_with?(' Next Scheduled Meeting')
      # end

end

