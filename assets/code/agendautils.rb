#!/usr/bin/env ruby
# Read town agenda materials HTML listing data into JSON
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

module AgendaUtils
  DESCRIPTION = <<-HEREDOC
  AgendaUtils: Utility functions for parsing NOVUS Agenda pages
  - Parse HTML listings of multiple agendas, and then download individual agenda HTML pages
  - Parse attachment listings in CoverSheet.aspx pages
  - Attempt to add video links to ACMi when available 
  
  Users go to a board agenda page for ARB:
  https://www.arlingtonma.gov/town-governance/all-boards-and-committees/redevelopment-board/agendas-minutes
  
  Which embeds an IFrame of this, parseable by parse_list_html() once you search for some meetings
  https://arlington.novusagenda.com/agendapublic/meetingsresponsive.aspx?MeetingType=45 ARB
  https://arlington.novusagenda.com/agendapublic/meetingsresponsive.aspx?MeetingType=50 Select board
  HEREDOC
  extend self
  require 'nokogiri'
  require 'open-uri'
  require 'net/http'
  require 'uri'
  
  NOVUS_URL = 'https://arlington.novusagenda.com/Agendapublic/' # CoverSheet.aspx?ItemID=7186&MeetingID=881
  SELECT = 'select'
  ARB = 'arb'
  SCHOOL = 'school' 
  FINCOM = 'fincom'
  ACMI_URLS = {  # january-27-2020
    SELECT => 'https://acmi.tv/videos/select-board-meeting-',
    ARB => 'https://acmi.tv/videos/redevelopment-board-meeting-',
    SCHOOL => 'https://acmi.tv/videos/school-committee-meeting-',
    FINCOM => 'https://acmi.tv/videos/finance-committee-meeting-'
  }
  # Various keys into hash structure used by all modules
  ERROR = 'error'
  STACK = 'stack'
  NOTICE = 'notice'
  ROWS = 'rows'
  ITEMS = 'items'
  ITEMNUM = 'num'
  ITEMLINK = 'url'
  TITLE = 'title'
  DETAILS = 'details'
  START_TIME = 'time'
  LOCATION = 'location'
  VIEWURL = 'viewurl'
  PDFURL = 'pdfurl'
  MINUTESURL = 'minurl'
  DATE = 'date'
  ISODATE = 'isodate'
  DOCKETS = 'dockets'
  AGENDA = 'agenda'
  AGENDAS = 'agendas'
  BYLAWS = 'bylaws'
  ATTACHMENTS = 'attachments'
  VIDEO = 'video'
  SUBHEAD = 'subhead'  
  CROSSINDEX = 'crossindex'
  CORRESPONDENCE = 'correspondence'
  CORRESPONDENCE_MATCH = /Correspondence received/i
  COVERSHEET_MATCH = /CoverSheet.aspx\?ItemID=\d{1,5}&MeetingID=\d{1,5}/
  BOGUS_CHAR = " " # Not sure where this comes from in the html
  FILENAME = 'filename'
  
  # Add coversheet data to existing meeting hash
  # @param hash of parsed meetings, any type
  # Side Effect: mutates original data
  def add_coversheets(meeting)
    # Find *any* Coversheet references and expand them
    puts "DEBUG: ----"
    puts meeting.inspect
    meeting[AGENDA][ITEMS].each do |item|
      urls = [] 
      urls << item[ITEMLINK] if item.has_key?(ITEMLINK)
      # Note: depending on type of agenda, links may be embedded in [DETAILS]
      matches = item[DETAILS].scan(COVERSHEET_MATCH) if item[DETAILS]
      urls = (urls + matches).uniq if matches
      urls.each do |url|
        attach = parse_coversheet(open(NOVUS_URL + url))
        if attach
          if item.has_key?(ATTACHMENTS)
            item[ATTACHMENTS].merge!(attach)
          else
            item[ATTACHMENTS] = attach
          end
        end
      end
    end
  end
  
  # Parse a CoverSheet.aspx, typically for correspondence received links
  # @param io to read
  # @return hash of correspondences {url => [filename, description]} or nil if no attachments therein
  def parse_coversheet(io)
    data = {}
    begin
      doc = Nokogiri::HTML(io)
      table = doc.css('#myTabContent table')[0] # First table inside the myTabContent div
      rows = doc.css('tbody table tr').drop(2) # Remove two header rows
      log("#{__method__.to_s}() Parsing attachments table, children #{rows.length}")
      rows.each do |row|
        data[row.elements[1].children[0]['href']] = 
        [
          row.elements[2].text.strip,
          row.elements[3].text.strip
        ]
      end
    rescue StandardError => e
      data[ERROR] = e.message + e.backtrace.join("\n\t")
    end
    return data unless data.empty?
  end
  
  # Add ACMi Video link for this agenda item, if one is available
  # @param agenda hash
  # Side effect: adds [VIDEO] if link is good/200
  def add_video(type, agenda)
    if agenda.has_key?(DATE)
      # Don't lookup if a link already exists (if we're re-processing existing data)
      return if agenda.has_key?(VIDEO)
      url = ACMI_URLS[type] + Date.strptime(agenda[DATE], "%m/%d/%y").strftime("%B-%-d-%Y").downcase + '/'
      rsp = Net::HTTP.get_response(URI.parse(url))
      if rsp.kind_of?(Net::HTTPSuccess)
        agenda[VIDEO] = url
      end
    end
  end
  
  # Bottleneck output - future use
  def log(s)
    puts s
  end  
end
