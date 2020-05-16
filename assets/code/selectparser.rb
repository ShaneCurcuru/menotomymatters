#!/usr/bin/env ruby
# Parse Select Board agendas
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

module SelectParser
  DESCRIPTION = <<-HEREDOC
  AgendaParser: Parse Select Board agendas with subheads and individual correspondences
  HEREDOC
  extend self
  require 'nokogiri'
  require_relative 'agendautils'
  
  # Parse a Select Board agenda page and output array of hashes of semi-structured data
  # This is customized to the specific Select agenda formats from 2020
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
      # Process all remaining tables depending on cell contents (order may be random or repeated)
      data[AgendaUtils::ITEMS] = []
      tables.each do |table|
        item = parse_row(table, parentid)
        data[AgendaUtils::ITEMS] << item if item
      end
    rescue StandardError => e
      data[AgendaUtils::ERROR] = "#{id} #{e.message}"
      data[AgendaUtils::STACK] = e.backtrace.join("\n\t")
    end
    return data
  end
  
  LOCAL_PREFIX = '<a href="https://arlington.novusagenda.com/Agendapublic/'
  FULL_PREFIX = '<a href="'
  LINK_POSTFIX = '"><i class="fa fa-fw fa-file-alt" aria-hidden="true"></i></a> '
  SELECT_ACTIONS_RX = /(For Approval:|Request:|Minutes of Meetings:|Presentation:|Reappointments|Discussion:|Discussion & Approval:|Discussion & Vote:|Request:)/
  SELECT_ACTIONS = [
    'For Approval:',
    'Minutes of Meetings:',
    'Presentation:',
    'Reappointments',
    'Discussion & Approval:',
    'Discussion & Vote:',
    'Discussion:',
    'Request:'
  ]
  
  # Parse a single "row" (a sub <table>) element of a Select agenda
  # @param table element
  # @return hash of data; or nil if blank spacer
  def parse_row(table, parentid)
    item = {}
    subhead = table.css('.style2') # Simple case: subheader in single cell
    if subhead.any?
      txt = subhead.text.strip
      unless txt.empty?
        item[AgendaUtils::TITLE] = txt
        item[AgendaUtils::SUBHEAD] = 'true'
      end
    else
      cells = table.css('.style1, .style4')
      # Aggregate all non-blank cells that match; these agendas mix different chunks
      blob = ''
      cells.each do |cell|
        txt = cell.text.strip
        if /\A(?<item_num>\d+)\.\Z/ =~ txt
          blob.concat("<span class='itemnum' id='#{parentid}_#{item_num}'>#{item_num}.</span>")
        elsif txt.length > 0
          # <a href="https://arlington.novusagenda.com/Agendapublic/{{ lineitm.url }}"><i class="fa fa-fw fa-file-alt" aria-hidden="true"></i> Item attachments</a>
          anchors = cell.css('a')
          anchors.each do |a|
            /http/ =~ a['href'] ? blob.concat(FULL_PREFIX, a['href'], LINK_POSTFIX) : blob.concat(LOCAL_PREFIX, a['href'], LINK_POSTFIX)
          end
          if SELECT_ACTIONS_RX =~ txt # Wow, this is inefficient
            SELECT_ACTIONS.each do |act|
              txt = txt.gsub(act, "<span class='itemact'>#{act}</span>")
            end
          end
          blob.concat(txt.gsub("\r\n", "\n"), "\n\n")
        end 
      end
      unless blob.empty?
        item[AgendaUtils::DETAILS] = blob
        item['nextmtg'] = true if blob.start_with?(' Next Scheduled Meeting')
      end
    end
    if item.any?
      return item
    else
      return nil
    end
  end
end
