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

  https://arlington.novusagenda.com/agendapublic/meetingsresponsive.aspx?MeetingType=45 ARB
  https://arlington.novusagenda.com/agendapublic/meetingsresponsive.aspx?MeetingType=50 Select board
  School Committee meetings and the many, many subcommittees and other bodies: all of them:
  https://arlington.novusagenda.com/agendapublic/meetingsresponsive.aspx?MeetingType=2&Meetingtype=3&Meetingtype=4&Meetingtype=5&Meetingtype=6&Meetingtype=7&Meetingtype=8&Meetingtype=9&Meetingtype=10&Meetingtype=11&Meetingtype=12&Meetingtype=13&Meetingtype=33&Meetingtype=34&Meetingtype=35&Meetingtype=37&Meetingtype=38&Meetingtype=39&Meetingtype=40&Meetingtype=41&Meetingtype=44&Meetingtype=55
  All NovusAGENDA meeting types
	MeetingType=46 Annual Town Meeting
	MeetingType=49 Board of Health
	MeetingType=1 Board of Selectmen Meeting
	MeetingType=52 Conservation Commission Meeting
	MeetingType=6 Negotiations Subcommittee: AAA
	MeetingType=7 Negotiations Subcommittee: AEA
	MeetingType=8 Negotiations Subcommittee: Bus
	MeetingType=9 Negotiations Subcommittee: Cafeteria
	MeetingType=10 Negotiations Subcommittee: Traffic Supervisors
	MeetingType=11 Negotiations Subcommittee: Unit C
	MeetingType=45 Redevelopment Board
	MeetingType=5 School Committee Executive Session
	MeetingType=39 School Committee Meeting
	MeetingType=4 School Committee Organizational Meeting
	MeetingType=2 School Committee Regular Meeting
  MeetingType=3 School Committee Special Meeting
	MeetingType=40 School Committee Superintendent Retreat
	MeetingType=50 Select Board Meeting
	MeetingType=47 Special Town Meeting
	MeetingType=33 Standing Subcommittee: Accountablity/Curriculum
	MeetingType=12 Standing Subcommittee: Budget
	MeetingType=13 Standing Subcommittee: Community Relations
	MeetingType=34 Standing Subcommittee: Facilities
	MeetingType=35 Standing Subcommittee: Policies and Procedures
	MeetingType=44 Standing Subcommittee: SEPAC
	MeetingType=37 Standing Subcommittee: Superintendent Evaluation
	MeetingType=55 Standing Subcommittee: Superintendent Search
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
  DOWNLOAD_URLS = {
    SELECT => 'https://arlington.novusagenda.com/agendapublic/meetingsresponsive.aspx?MeetingType=50',
    ARB => 'https://arlington.novusagenda.com/agendapublic/meetingsresponsive.aspx?MeetingType=45',
    SCHOOL => 'https://arlington.novusagenda.com/agendapublic/meetingsresponsive.aspx?MeetingType=2&Meetingtype=3&Meetingtype=4&Meetingtype=39',
    FINCOM => 'TBD'
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
  
  # Download various meeting agendas from a preparsed meeting agenda listing html (or use cached files)
  # @param type of agenda: SELECT, ARB, etc. (points to a parser)
  # @param dir to place files
  # @param json hash from parse_meeting_list() output
  # @return array of agenda detail hashes, annotated with filename; or with error
  # Side effect: creates local dir/2020-05-05-type.html files
  def download_meetings(type, dir, meetings)
    raise ArgumentError, "No type #{type} of meeting to download provided" if type.nil? || type.empty?
    puts "WARNING: No working directory #{dir} provided, using ." unless dir
    AgendaUtils.log("#{__method__.to_s}() Downloading meeting agendas of #{type} meetings #{meetings.length} into #{dir}")
    meetings.each do |isodate, meeting|
      meeting.has_key?(FILENAME) ? fn = meeting[FILENAME] : fn = File.join(dir, "#{isodate}-#{type}.html")
      if File.file?(fn)
        # No-op: AgendaUtils.log("Found cached file #{fn}")
      else    
        AgendaUtils.log("Downloading file #{fn}")
        begin
          File.open(fn, "w") do |f|
            f.write(open(NOVUS_URL + meeting[VIEWURL]).read)
          end
          meeting[FILENAME] = fn
        rescue StandardError => e
          meeting[ERROR] = e.message
          meeting[STACK] = e.backtrace.join("\n\t")
        end
      end
    end
    return meetings
  end

  # Parse an meeting agenda listing html and output array of hashes of semi-structured data
  # Download html source from: view-source:https://arlington.novusagenda.com/agendapublic/meetingsresponsive.aspx?MeetingType=45
  #   after selecting the meetings you want
  # @param io to parse as html of the detail agenda page
  # @return hash by ISODATE of agenda metadata hashes
  def parse_meeting_list(io)
    meetings = {}
    doc = Nokogiri::HTML(io)
    table = doc.css('#myTabContent table')[0] # First table inside the myTabContent div
    rows = table.css('tr').drop(1) # Remove the header row
    log("#{__method__.to_s}() Parsing agenda html list table, children #{rows.length}")
    rows.each do |row|
      next if 'collapse' == row['class'] # Skip duplicate mobile-only rows, if any
      meeting = parse_meeting_item(row)
      meetings[meeting[ISODATE]] = meeting
    end
    return meetings
  end
  
  # Parse an meeting agenda listing html item row 
  # @param row of tr holding the item
  # @return hash of this agenda's links
  def parse_meeting_item(row)
    meeting = {}
    begin
      meeting[DATE] = row.css('td:nth-child(2)').text.strip
      meeting[ISODATE] = Date.strptime(meeting[DATE], "%m/%d/%y").strftime("%Y-%m-%d")
      meeting[TITLE] = row.css('td:nth-child(3) label').text.strip
      meeting[LOCATION] = row.css('td:nth-child(4)').text.strip
      a = row.css('td:nth-child(5) a')
      if a.any?
        meeting[VIEWURL] = a[0]['onclick'].split("'")[1]
      end
      a = row.css('td:nth-child(6) a')
      if a.any?
        meeting[PDFURL] = a[0]['href']
      end
      a = row.css('td:nth-child(7) a')
      if a.any?
        meeting[MINUTESURL] = a[0]['href']
      end
    rescue StandardError => e
      meeting[ERROR] = e.message
      meeting[STACK] = e.backtrace.join("\n\t")
    end
    return meeting
  end

  # Add coversheet data to existing meeting hash
  # @param hash of parsed meetings, any type
  # Side Effect: mutates original data
  def add_coversheets(meeting)
    # Find *any* Coversheet references and expand them
    # puts "DEBUG " + meeting.inspect
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
      # log("#{__method__.to_s}() Parsing attachments table, children #{rows.length}")
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
