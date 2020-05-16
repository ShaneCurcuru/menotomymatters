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

module ARBParser
  DESCRIPTION = <<-HEREDOC
  ARBParser: Parse ARB Agendas with custom docket and bylaw annotations
  HEREDOC
  extend self
  require 'nokogiri'
  require_relative 'agendautils'
  
  ARB_DOCKET_MATCH = /docket.{1,2}(\d\d\d\d),?([^*]+)/i
  ARB_BYLAW_MATCH = /ARTICLE (\d+) ZONING/
  ARB_BYLAW_MATCH2 = /ARTICLE \d+ ZONING [^a-z]*/
  
  # TODO update to output isodate => hash format (see transform/crossindex)
  # Parse a ARB Board agenda page and output array of hashes of semi-structured data
  # This is customized to the specific Select agenda formats from 2020
  # @param io stream to read
  # @param id identifier of stream (filename or URL)
  # @param parentid for anchors
  # @return data hash listing agenda metadata and details; includes AgendaUtils::ERROR key if any
  def parse(io, id, parentid)
    agenda = {}
    begin
      doc = Nokogiri::HTML(io)
      tables = doc.css('td > table') # A table inside a cell
      AgendaUtils.log("#{__method__.to_s}() Parsing agenda table rows: #{tables.length} for #{id}")
      raise ArgumentError.new("Agenda data not found; perhaps meeting was cancelled?") if tables.length < 3
      # Grab header info from first table
      agenda[AgendaUtils::NOTICE] = tables[0].css("[colspan]#column1").text.strip.gsub(/\s+/, ' ')
      # Skip second table (just spacer)
      # Third table is rows of embedded agenda
      rows = tables[2].elements
      agenda[AgendaUtils::ROWS] = rows.length
      agenda[AgendaUtils::ITEMS] = []
      tmp = rows.first
      header = tmp.next_element
      detail = header.next_element
      while detail do 
        a = {}
        dockets = {}
        bylaws = {}  
        # Parse header row, including number, title, and possible link
        style3 = header.css(".style3")
        a[AgendaUtils::ITEMNUM] = style3[0].text
        a[AgendaUtils::TITLE] = style3[1].text.strip.gsub(/\s+/, ' ')
        style3link = style3.css("a")
        a[AgendaUtils::ITEMLINK] = style3link[0]['href'] if style3link.any?
        
        # Parse sub-table of details; just nned two cells within subtable
        cells = detail.css("tbody > tr > td")
        if cells.length > 1
          # Split the time and details out
          a[AgendaUtils::START_TIME] = cells[0].text.strip.gsub(/\s+/, ' ')
          text = ''
          # Various types of detail table rows exist for ARB agendas
          # Several <p> elements
          # Single chunk of text (usually short)
          # Single TD with text and <br/> separated lines
          # No table at all, just a .style4 td with text inside
          hasparas = cells[1].css('p')
          if hasparas.any?
            paras = cells[1].elements
            paras.each do |p|
              text += p.text.strip.gsub(/\s+/, ' ').gsub('•',"\n- ") + "\n\n"
              strongs = p.css('strong')
              strongs.each do |txt| # Parse docket numbers or bylaw numbers
                dmatch = ARB_DOCKET_MATCH.match(txt)
                dockets[dmatch.captures[0]] = dmatch.captures[1].strip if dmatch
                bmatch = ARB_BYLAW_MATCH.match(txt)
                bylaws[bmatch[1]] = txt.text if bmatch
              end
            end
          else
            text = cells[1].text.strip.gsub(/\s+/, ' ').gsub('•',"\n- ")
            strongs = cells[1].css('strong')
            strongs.each do |txt| # Parse docket number and remainder
              dmatch = ARB_DOCKET_MATCH.match(txt)
              dockets[dmatch.captures[0]] = dmatch.captures[1].strip if dmatch
              bmatch = ARB_BYLAW_MATCH.match(txt)
              bylaws[bmatch[1]] = txt.text if bmatch
            end
          end
          d = text.scan(/docket.{1,2}(\d\d\d\d)/i) # Fallback to catch unsual docket discussions
          d.each do |dd|
            dockets[dd[0]] = '' unless dockets.has_key?(dd[0])
          end
          a[AgendaUtils::DETAILS] = text
          a[AgendaUtils::DOCKETS] = dockets if dockets.any?
          a[AgendaUtils::BYLAWS] = bylaws if bylaws.any?
        else
          # Simplistic case where there's only one cell, or no subtable at all
          if cells.any?
            a[AgendaUtils::DETAILS] = cells[0].text.strip.gsub(/\s+/, ' ').gsub('•',"\n- ")
          else
            # Fallback to simply taking the td content itself; leave linebreaks
            style4 = detail.css(".style4")
            a[AgendaUtils::DETAILS] = style4[0].text.strip.gsub(/[ \t]+/, ' ').gsub('•',"\n- ")
          end
        end
        # Backup scan for bylaws, they are often in different formats
        unless a.has_key?(AgendaUtils::BYLAWS)
          tmp = a[AgendaUtils::DETAILS].scan(ARB_BYLAW_MATCH2)
          tmp.each do |bmatch|
            bylaws[ARB_BYLAW_MATCH.match(bmatch)[1]] = bmatch
          end
          a[AgendaUtils::BYLAWS] = bylaws if bylaws.any?
        end
        # Backup scan for dockets in titles
        if dockets.empty?
          dmatch = ARB_DOCKET_MATCH.match(a[AgendaUtils::TITLE])
          dockets[dmatch.captures[0]] = dmatch.captures[1].strip if dmatch
          a[AgendaUtils::DOCKETS] = dockets if dockets.any?
        end
        # Organize any correspondence
        if AgendaUtils::CORRESPONDENCE_MATCH =~ a[AgendaUtils::TITLE] 
          arr = a[AgendaUtils::DETAILS].sub(AgendaUtils::CORRESPONDENCE_MATCH.source, '').sub(/from:?\s?/, '').gsub(AgendaUtils::BOGUS_CHAR, '').strip.split(/\r?\n+/)
          a[AgendaUtils::CORRESPONDENCE] = arr.reject{|frm| frm.length < 1} if arr.any?
        end
        # Stuff our item into array
        agenda[AgendaUtils::ITEMS] << a
        header = detail.next_element
        detail = nil
        detail = header.next_element if header    
      end
    rescue StandardError => e
      agenda[AgendaUtils::ERROR] = "#{id} #{e.message}"
      agenda[AgendaUtils::STACK] = e.backtrace.join("\n\t")
    end
    return agenda
  end
  
  # Crossindex an existing json of parsed agendas
  # @param hash to annotate
  # Side effect: adds metadata at head and in items
  def crossindex(json)
    errors = []
    dockets = {}
    begin
      AgendaUtils.log("#{__method__.to_s}() Parsing agendas # #{json.length}")
      crossindex = {}
      crossindex[AgendaUtils::TITLE] = AgendaUtils::CROSSINDEX
      meetings = json.each
      meetings.each do |meeting|
        agenda = meeting[AgendaUtils::AGENDA]
        next unless agenda 
        next unless agenda.has_key?(AgendaUtils::ITEMS)
        agenda[AgendaUtils::ITEMS].each do |item|
          if item.has_key?(AgendaUtils::DOCKETS)
            item[AgendaUtils::DOCKETS].each do |d, val|
              # Cache and fillin missing addresses (best attempt)
              if dockets.has_key?(d)
                if ''.eql?(dockets[d])
                  dockets[d] = val
                elsif ''.eql?(val)
                  item[AgendaUtils::DOCKETS][d] = dockets[d]
                elsif ! dockets[d].eql?(val)
                  AgendaUtils.log("DEBUG: Mismatched addresses(#{d}, #{meeting[AgendaUtils::ISODATE]}, #{item[AgendaUtils::ITEMNUM]}): |#{dockets[d]}|<>|#{item[AgendaUtils::DOCKETS][d]}|")
                end
              else
                dockets[d] = val
              end
              # OMG I really need more coffee, this is spaghetti
              if crossindex.has_key?(d)
                crossindex[d]['meetings'] << meeting[AgendaUtils::ISODATE]
              else
                crossindex[d] = {}
                crossindex[d]['address'] = val
                crossindex[d]['meetings'] = [meeting[AgendaUtils::ISODATE]]
              end
            end
          end
        end
      end
    rescue StandardError => e
      errors << e.message
      errors << e.backtrace.join("\n\t")
    end
    json << crossindex 
    json << errors if errors.any?
    return json
  end
  
  # TODO Remove this and add equivalent to parse() or crossindex()
  # Changed data format to make display simpler
  # Transform the originally parsed array w/crossindex into a single hash
  def transform(json)
    transformed = {}
    AgendaUtils.log("#{__method__.to_s}() Parsing agendas # #{json.length}")
    agendas, crossindex = json.partition { |h| h.has_key?(AgendaUtils::ISODATE) }
    agendas.each do |agenda|
      transformed[agenda[AgendaUtils::ISODATE]] = agenda
    end
    transformed[AgendaUtils::CROSSINDEX] = {}
    crossindex[0].each do |k, val|
      if val.kind_of?(Hash)
        transformed[AgendaUtils::CROSSINDEX][k] = {} # Force new ordering in hash
        transformed[AgendaUtils::CROSSINDEX][k]['address'] = val['address']
        transformed[AgendaUtils::CROSSINDEX][k]['purpose'] = ''
        transformed[AgendaUtils::CROSSINDEX][k]['owner'] = ''
        transformed[AgendaUtils::CROSSINDEX][k]['meetings'] = val['meetings']
      else
        # no-op, drop string
      end
    end
    return transformed
  end
end
