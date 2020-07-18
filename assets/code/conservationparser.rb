#!/usr/bin/env ruby
# Parse ARB Agendas
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

module ConservationParser
  DESCRIPTION = <<-HEREDOC
  ARBParser: Parse Conservation Commission Agendas with nested table structure.
  HEREDOC
  extend self
  require 'nokogiri'
  require 'json'
  require_relative 'agendautils'
  
  ARB_DOCKET_MATCH = /docket.{1,2}(\d\d\d\d),?([^*]+)/i
  ARB_BYLAW_MATCH = /ARTICLE (\d+) ZONING/
  ARB_BYLAW_MATCH2 = /ARTICLE \d+ ZONING [^a-z]*/
  
  # Parse an Conservation Commission Board agenda page and output hash of items
  # This is customized to the specific Conservation Commission agenda formats from Nov 2019-current
  # @param io stream to read
  # @param id identifier of stream (filename or URL)
  # @param parentid for anchors
  # @return data hash listing agenda metadata and details; includes AgendaUtils::ERROR key if any
  def parse(io, id, parentid)
    agenda = {}
    begin
      doc = Nokogiri::HTML(io)
      tables = doc.css('td > table') # A table inside a cell
      raise ArgumentError.new("Agenda data not found; perhaps meeting was cancelled?") if tables.length < 3
      AgendaUtils.log("#{__method__.to_s}() Parsing agenda table rows: #{tables.length} for #{id}")
      # Grab header info from first table
      agenda[AgendaUtils::NOTICE] = tables.shift.css("[colspan]#column1").text.strip.gsub(/\s+/, ' ')

      # Following pairs of tables are alternately agenda item number/header or details of an agenda item
      agenda[AgendaUtils::ROWS] = tables.length
      agenda[AgendaUtils::ITEMS] = []
      tables.each_slice(2) do | header, details |
        item = {}
        style1 = header.css('.style1')
        item[AgendaUtils::ITEMNUM] = style1[0].text.strip
        item[AgendaUtils::TITLE] = style1[1].text.strip
        # Agenda item details table has:
        # - blank tr
        # - data tr with
        #   id=column2 .style1 subheadernumber
        #   id=column3 colspan=4 .style1
        #     Either bare link, or bare text node, or set of <p> elements
        blobs = ''
        links = []
        details.css('tr').each do | tr |
          styles = tr.css('.style1, .style2, .style4')
          puts "DEBUG style124 row count: #{styles.length}"
          styles.each do | cell |
            case cell['class']
            when 'style1' # Blank, or a subheader
              tmp = cell.text.strip
              blobs << "\n\n<span class='subhead'>#{tmp}</span>" unless tmp.empty?
            when 'style2' # Single link (usually)
              a = cell.css('a')
              if a.any?
                links << a[0]['href']
                blobs << " <a href='#{a[0]['href']}'>#{a[0].content.strip}</a> "
              end
            when 'style4' # Contains paragraphs etc.
              parse_node(cell, blobs, links)
            else
              # no-op
            end
          end
        end
        #item[AgendaUtils::ITEMLINK] = ''
        item[AgendaUtils::DETAILS] = blobs
        agenda[AgendaUtils::ITEMS] << item
      end
    rescue StandardError => e
      agenda[AgendaUtils::ERROR] = "#{id} #{e.message}"
      agenda[AgendaUtils::STACK] = e.backtrace.join("\n\t")
    end
    return agenda
  end

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
        blobs << "<a href='#{node['href']}'>#{node.content.strip}</a> "
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
